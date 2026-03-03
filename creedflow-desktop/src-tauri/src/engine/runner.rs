use crate::agents::{self, Agent};
use crate::backends::{AgentResult, BackendRouter, CliBackend, OutputEvent, TaskInput};
use crate::db::models::{AgentTask, AgentType};
use crate::db::Database;
use crate::services::mcp::MCPConfigGenerator;
use rusqlite::params;
use std::sync::Arc;
use tauri::Emitter;
use tokio::sync::Mutex;
use tokio::time::{timeout, Duration};

/// Result of a task execution.
pub struct TaskRunResult {
    pub output: String,
    pub cost_usd: Option<f64>,
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub duration_ms: Option<i64>,
    pub session_id: Option<String>,
    pub model: Option<String>,
    pub backend_type: String,
    pub success: bool,
    pub error: Option<String>,
}

/// Executes a task: selects backend, builds prompt, spawns CLI, streams output.
pub struct TaskRunner;

impl TaskRunner {
    /// Execute a task end-to-end.
    pub async fn run(
        task: &AgentTask,
        router: &BackendRouter,
        db: &Arc<Mutex<Database>>,
        app_handle: Option<&tauri::AppHandle>,
        revision_memory: Option<String>,
    ) -> TaskRunResult {
        let agent_type = AgentType::from_str(&task.agent_type);
        let agent = agents::resolve_agent(&agent_type);

        // 1. Select backend
        let backend = match router.select_backend(&agent.backend_preferences()).await {
            Some(b) => b,
            None => {
                return TaskRunResult {
                    output: String::new(),
                    cost_usd: None,
                    input_tokens: None,
                    output_tokens: None,
                    duration_ms: None,
                    session_id: None,
                    model: None,
                    backend_type: "none".to_string(),
                    success: false,
                    error: Some("No backend available".to_string()),
                };
            }
        };

        let backend_type_str = backend.backend_type().as_str().to_string();

        // 2. Write backend to DB on dispatch
        {
            let db_lock = db.lock().await;
            let _ = db_lock.conn.execute(
                "UPDATE agentTask SET backend = ?2, updatedAt = datetime('now') WHERE id = ?1",
                params![task.id, backend_type_str],
            );
        }

        // Emit backend info to frontend
        if let Some(handle) = app_handle {
            let _ = handle.emit("task-backend-assigned", serde_json::json!({
                "taskId": task.id,
                "backend": backend_type_str,
            }));
        }

        // 3. Build prompt with revision memory
        let full_prompt = Self::build_full_prompt(agent.as_ref(), task, revision_memory);

        // 4. Generate MCP config if needed
        let mcp_config_path = if let Some(servers) = agent.mcp_servers() {
            let server_refs: Vec<&str> = servers.iter().map(|s| s.as_str()).collect();
            let temp_dir = std::env::temp_dir().join("creedflow-mcp");
            MCPConfigGenerator::generate(&server_refs, &temp_dir).ok()
        } else {
            None
        };

        // 5. Build TaskInput
        let working_dir = Self::resolve_working_dir(task, db).await;
        let input = TaskInput {
            prompt: full_prompt,
            system_prompt: agent.system_prompt().to_string(),
            working_directory: working_dir,
            allowed_tools: agent.allowed_tools(),
            max_budget_usd: Some(agent.max_budget_usd()),
            timeout_seconds: agent.timeout_seconds(),
            mcp_config_path: mcp_config_path.map(|p| p.to_string_lossy().to_string()),
            json_schema: None,
            attachments: vec![],
        };

        // 6. Execute with timeout
        let timeout_duration = Duration::from_secs(agent.timeout_seconds() as u64);
        let start = std::time::Instant::now();

        match timeout(timeout_duration, Self::execute_backend(backend, input, task, app_handle)).await {
            Ok(result) => {
                let elapsed = start.elapsed().as_millis() as i64;
                match result {
                    Ok(mut r) => {
                        r.duration_ms = Some(elapsed);
                        r.backend_type = backend_type_str;
                        r
                    }
                    Err(e) => TaskRunResult {
                        output: String::new(),
                        cost_usd: None,
                        input_tokens: None,
                        output_tokens: None,
                        duration_ms: Some(elapsed),
                        session_id: None,
                        model: None,
                        backend_type: backend_type_str,
                        success: false,
                        error: Some(e),
                    },
                }
            }
            Err(_) => {
                // Timeout — cancel via backend
                backend.cancel_all().await;
                TaskRunResult {
                    output: String::new(),
                    cost_usd: None,
                    input_tokens: None,
                    output_tokens: None,
                    duration_ms: Some(timeout_duration.as_millis() as i64),
                    session_id: None,
                    model: None,
                    backend_type: backend_type_str,
                    success: false,
                    error: Some(format!("Task timed out after {}s", agent.timeout_seconds())),
                }
            }
        }
    }

    /// Build the full prompt: agent prompt + revision memory.
    fn build_full_prompt(
        agent: &dyn Agent,
        task: &AgentTask,
        revision_memory: Option<String>,
    ) -> String {
        let base_prompt = agent.build_prompt(task);

        match revision_memory {
            Some(memory) if !memory.is_empty() => {
                format!(
                    "{}\n\n--- REVISION CONTEXT ---\n{}\n--- END REVISION CONTEXT ---",
                    base_prompt, memory
                )
            }
            _ => base_prompt,
        }
    }

    /// Execute via the selected backend and stream output.
    async fn execute_backend(
        backend: &dyn CliBackend,
        input: TaskInput,
        task: &AgentTask,
        app_handle: Option<&tauri::AppHandle>,
    ) -> Result<TaskRunResult, String> {
        let (id, mut rx) = backend.execute(input).await?;
        let mut full_output = String::new();
        let mut final_result: Option<AgentResult> = None;

        while let Some(event) = rx.recv().await {
            match event {
                OutputEvent::Text(text) => {
                    full_output.push_str(&text);
                    // Stream to frontend
                    if let Some(handle) = app_handle {
                        let _ = handle.emit("task-output", serde_json::json!({
                            "taskId": task.id,
                            "type": "text",
                            "content": text,
                        }));
                    }
                }
                OutputEvent::ToolUse(tool) => {
                    if let Some(handle) = app_handle {
                        let _ = handle.emit("task-output", serde_json::json!({
                            "taskId": task.id,
                            "type": "tool_use",
                            "content": tool,
                        }));
                    }
                }
                OutputEvent::System { session_id, model } => {
                    if let Some(handle) = app_handle {
                        let _ = handle.emit("task-output", serde_json::json!({
                            "taskId": task.id,
                            "type": "system",
                            "sessionId": session_id,
                            "model": model,
                        }));
                    }
                }
                OutputEvent::Result(result) => {
                    full_output = result.output.clone();
                    final_result = Some(result);
                }
                OutputEvent::Error(err) => {
                    // Check for rate-limit signals before returning error
                    if let Some(signal) = crate::services::health::RateLimitDetector::detect(&err) {
                        return Err(format!("RATE_LIMITED:{}:{}", signal, err));
                    }
                    return Err(err);
                }
            }
        }

        let _ = id; // execution ID tracked by backend internally

        match final_result {
            Some(result) => Ok(TaskRunResult {
                output: result.output,
                cost_usd: result.cost_usd,
                input_tokens: result.input_tokens,
                output_tokens: result.output_tokens,
                duration_ms: result.duration_ms,
                session_id: result.session_id,
                model: result.model,
                backend_type: String::new(), // filled by caller
                success: true,
                error: None,
            }),
            None => {
                // No Result event — use accumulated text output
                if full_output.is_empty() {
                    Err("Backend produced no output".to_string())
                } else {
                    Ok(TaskRunResult {
                        output: full_output,
                        cost_usd: None,
                        input_tokens: None,
                        output_tokens: None,
                        duration_ms: None,
                        session_id: None,
                        model: None,
                        backend_type: String::new(),
                        success: true,
                        error: None,
                    })
                }
            }
        }
    }

    /// Resolve the working directory for a task from its project.
    async fn resolve_working_dir(task: &AgentTask, db: &Arc<Mutex<Database>>) -> String {
        let db_lock = db.lock().await;
        let dir: Option<String> = db_lock
            .conn
            .query_row(
                "SELECT directoryPath FROM project WHERE id = ?1",
                [&task.project_id],
                |row| row.get(0),
            )
            .ok();
        dir.filter(|d| !d.is_empty())
            .unwrap_or_else(|| ".".to_string())
    }
}
