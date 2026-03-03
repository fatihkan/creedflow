use crate::backends::{
    BackendRouter, CliBackend,
    claude::ClaudeBackend,
    codex::CodexBackend,
    gemini::GeminiBackend,
    ollama::OllamaBackend,
    lmstudio::LMStudioBackend,
    llamacpp::LlamaCppBackend,
    mlx::MLXBackend,
};
use crate::db::Database;
use crate::db::models::{AgentTask, AgentType};
use crate::engine::runner::{TaskRunner, TaskRunResult};
use crate::engine::scheduler::AgentScheduler;
use crate::engine::task_queue::TaskQueue;
use crate::engine::retry::RetryPolicy;
use crate::services::git_branch_manager::GitBranchManager;
use crate::services::telegram::TelegramService;
use crate::services::notifications::NotificationService;
use crate::services::health::{BackendHealthMonitor, MCPHealthMonitor};
use crate::util::ndjson::extract_json;
use rusqlite::params;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::Emitter;
use tokio::sync::Mutex;
use tokio::time::{interval, Duration};

/// Central orchestration loop — polls TaskQueue every 2 seconds,
/// selects backend via BackendRouter, dispatches tasks to agents.
pub struct Orchestrator {
    db: Arc<Mutex<Database>>,
    task_queue: Arc<TaskQueue>,
    scheduler: Arc<AgentScheduler>,
    retry_policy: RetryPolicy,
    router: Arc<BackendRouter>,
    is_running: Arc<AtomicBool>,
    polling_handle: Mutex<Option<tokio::task::JoinHandle<()>>>,
    app_handle: Option<tauri::AppHandle>,
    telegram: Option<Arc<TelegramService>>,
    pub notification_service: Arc<NotificationService>,
    backend_health_monitor: Arc<BackendHealthMonitor>,
    mcp_health_monitor: Arc<MCPHealthMonitor>,
}

impl Orchestrator {
    pub fn new(
        db: Arc<Mutex<Database>>,
        max_concurrency: usize,
        app_handle: Option<tauri::AppHandle>,
    ) -> Self {
        let task_queue = Arc::new(TaskQueue::new(db.clone()));
        let scheduler = Arc::new(AgentScheduler::new(max_concurrency));

        // Initialize all backends
        let backends: Vec<Box<dyn CliBackend>> = vec![
            Box::new(ClaudeBackend::new()),
            Box::new(CodexBackend::new()),
            Box::new(GeminiBackend::new()),
            Box::new(OllamaBackend::new()),
            Box::new(LMStudioBackend::new()),
            Box::new(LlamaCppBackend::new()),
            Box::new(MLXBackend::new()),
        ];
        let router = Arc::new(BackendRouter::new(backends));

        let notification_service = Arc::new(NotificationService::new(db.clone()));
        let backend_health_monitor = Arc::new(BackendHealthMonitor::new(db.clone(), notification_service.clone()));
        let mcp_health_monitor = Arc::new(MCPHealthMonitor::new(db.clone(), notification_service.clone()));

        Self {
            db: db.clone(),
            task_queue,
            scheduler,
            retry_policy: RetryPolicy::default(),
            router,
            is_running: Arc::new(AtomicBool::new(false)),
            polling_handle: Mutex::new(None),
            app_handle,
            telegram: None,
            notification_service,
            backend_health_monitor,
            mcp_health_monitor,
        }
    }

    /// Configure Telegram notifications.
    pub fn set_telegram(&mut self, bot_token: String, chat_id: String) {
        self.telegram = Some(Arc::new(TelegramService::new(bot_token, chat_id)));
    }

    /// Start the orchestrator polling loop.
    pub async fn start(&self) -> Result<(), String> {
        if self.is_running.load(Ordering::SeqCst) {
            return Ok(());
        }

        // Recover orphaned tasks from previous crash
        self.task_queue.recover_orphaned_tasks().await?;

        self.is_running.store(true, Ordering::SeqCst);

        // Start health monitors
        self.backend_health_monitor.start().await;
        self.mcp_health_monitor.start().await;

        // Prune old notifications (older than 7 days)
        self.notification_service.prune_old(7).await;

        let is_running = self.is_running.clone();
        let task_queue = self.task_queue.clone();
        let scheduler = self.scheduler.clone();
        let app_handle = self.app_handle.clone();
        let db = self.db.clone();
        let router = self.router.clone();
        let retry_policy = RetryPolicy::default();
        let telegram = self.telegram.clone();
        let notification_service = self.notification_service.clone();

        let handle = tokio::spawn(async move {
            let mut tick = interval(Duration::from_secs(2));

            while is_running.load(Ordering::SeqCst) {
                tick.tick().await;

                // Try to dequeue a task
                match task_queue.dequeue().await {
                    Ok(Some(task)) => {
                        // Try to acquire a concurrency slot
                        if let Some(permit) = scheduler.try_acquire() {
                            let agent_type = AgentType::from_str(&task.agent_type);

                            // Validate creative agents have at least one MCP service configured
                            if is_creative_agent(&agent_type) {
                                let agent = crate::agents::resolve_agent(&agent_type);
                                if let Some(mcp_servers) = agent.mcp_servers() {
                                    let creative_names: Vec<&str> = mcp_servers.iter()
                                        .map(|s| s.as_str())
                                        .filter(|s| *s != "creedflow")
                                        .collect();
                                    let has_config = {
                                        let db_lock = db.lock().await;
                                        creative_names.iter().any(|name| {
                                            db_lock.conn.query_row(
                                                "SELECT COUNT(*) FROM mcpServerConfig WHERE name = ? AND isEnabled = 1",
                                                rusqlite::params![name],
                                                |row| row.get::<_, i64>(0),
                                            ).unwrap_or(0) > 0
                                        })
                                    };
                                    if !has_config {
                                        let service_list = creative_names.join(", ");
                                        let error_msg = format!(
                                            "No creative AI service configured. Go to Settings → MCP Servers to add an API key for {}.",
                                            service_list
                                        );
                                        log::warn!("Task {} failed: {}", task.id, error_msg);
                                        let _ = task_queue.fail(&task.id, &error_msg).await;
                                        drop(permit);
                                        continue;
                                    }
                                }
                            }

                            log::info!("Dispatching task {} ({})", task.id, task.agent_type);

                            // Emit event to frontend
                            if let Some(ref handle) = app_handle {
                                let _ = handle.emit("task-status-changed", serde_json::json!({
                                    "taskId": task.id,
                                    "status": "in_progress",
                                    "agentType": task.agent_type,
                                }));
                            }

                            // Spawn task execution in background
                            let task_queue_c = task_queue.clone();
                            let db_c = db.clone();
                            let router_c = router.clone();
                            let app_handle_c = app_handle.clone();
                            let telegram_c = telegram.clone();
                            let notif_c = notification_service.clone();

                            tokio::spawn(async move {
                                // Build revision memory if this is a retry
                                let revision_memory = if task.retry_count > 0 || task.revision_prompt.is_some() {
                                    Some(build_revision_memory(&task, &db_c).await)
                                } else {
                                    None
                                };

                                // Phase 3: Execute via TaskRunner
                                let result = TaskRunner::run(
                                    &task,
                                    &router_c,
                                    &db_c,
                                    app_handle_c.as_ref(),
                                    revision_memory,
                                ).await;

                                // Handle result
                                if result.success {
                                    // Write result to DB
                                    update_task_success(&task, &result, &db_c).await;

                                    // Record cost
                                    record_cost(&task, &result, &db_c).await;

                                    // Agent-specific completion handlers
                                    handle_agent_completion(&task, &result, &db_c, app_handle_c.as_ref()).await;

                                    // Git completion pipeline
                                    handle_git_completion(&task, &db_c, app_handle_c.as_ref()).await;

                                    // In-app + Telegram notification
                                    notif_c.emit(
                                        crate::db::models::NotificationCategory::Task,
                                        crate::db::models::NotificationSeverity::Success,
                                        &format!("Task Completed: {}", task.title),
                                        &format!("Agent: {} | Backend: {}", task.agent_type, result.backend_type),
                                    ).await;
                                    if let Some(ref tg) = telegram_c {
                                        let msg = format!(
                                            "✅ Task completed: {} ({})\nBackend: {}",
                                            task.title, task.agent_type, result.backend_type
                                        );
                                        let _ = tg.send_message(&msg).await;
                                    }
                                } else {
                                    let error_msg = result.error.unwrap_or_else(|| "Unknown error".to_string());
                                    log::error!("Task {} failed: {}", task.id, error_msg);

                                    // Check for rate limit
                                    if error_msg.starts_with("RATE_LIMITED:") {
                                        let backoff_secs = RetryPolicy::rate_limit_backoff(task.retry_count);
                                        log::warn!("Rate limited on task {}. Backoff {}s", task.id, backoff_secs);

                                        notif_c.emit(
                                            crate::db::models::NotificationCategory::RateLimit,
                                            crate::db::models::NotificationSeverity::Warning,
                                            &format!("Rate Limited: {}", task.title),
                                            &format!("Backing off for {}s before retry", backoff_secs),
                                        ).await;

                                        // Sleep for backoff then requeue
                                        tokio::time::sleep(Duration::from_secs(backoff_secs)).await;
                                        let _ = task_queue_c.requeue(&task.id).await;
                                    } else if retry_policy.should_retry(task.retry_count) {
                                        // Normal retry
                                        log::info!("Requeueing task {} (retry {})", task.id, task.retry_count + 1);
                                        let _ = task_queue_c.requeue(&task.id).await;
                                    } else {
                                        let _ = task_queue_c.fail(&task.id, &error_msg).await;

                                        // In-app + Telegram notification for failure
                                        notif_c.emit(
                                            crate::db::models::NotificationCategory::Task,
                                            crate::db::models::NotificationSeverity::Error,
                                            &format!("Task Failed: {}", task.title),
                                            &format!("Error: {}", error_msg),
                                        ).await;
                                        if let Some(ref tg) = telegram_c {
                                            let msg = format!(
                                                "❌ Task failed: {} ({})\nError: {}",
                                                task.title, task.agent_type, error_msg
                                            );
                                            let _ = tg.send_message(&msg).await;
                                        }
                                    }

                                    // Emit failure to frontend
                                    if let Some(ref handle) = app_handle_c {
                                        let _ = handle.emit("task-status-changed", serde_json::json!({
                                            "taskId": task.id,
                                            "status": "failed",
                                            "agentType": task.agent_type,
                                            "error": error_msg,
                                        }));
                                    }
                                }

                                // Release concurrency slot
                                drop(permit);
                            });
                        } else {
                            // No slot available — defer (don't count as retry)
                            let _ = task_queue.defer_task(&task.id).await;
                            log::debug!("No scheduler slot, deferring task {}", task.id);
                        }
                    }
                    Ok(None) => {
                        // No tasks ready
                    }
                    Err(e) => {
                        log::error!("TaskQueue dequeue error: {}", e);
                    }
                }
            }
        });

        *self.polling_handle.lock().await = Some(handle);
        Ok(())
    }

    /// Stop the orchestrator.
    pub async fn stop(&self) {
        self.is_running.store(false, Ordering::SeqCst);
        if let Some(handle) = self.polling_handle.lock().await.take() {
            handle.abort();
        }
        self.backend_health_monitor.stop().await;
        self.mcp_health_monitor.stop().await;
    }

    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::SeqCst)
    }
}

// ─── Helper Functions ────────────────────────────────────────────────────────

/// Build revision memory from previous attempts — reviews, errors, prior output.
async fn build_revision_memory(task: &AgentTask, db: &Arc<Mutex<Database>>) -> String {
    let mut memory = String::new();

    let db_lock = db.lock().await;

    // Previous reviews for this task
    let mut stmt = db_lock.conn.prepare(
        "SELECT score, verdict, summary, issues, suggestions FROM review WHERE taskId = ?1 ORDER BY createdAt DESC LIMIT 3"
    ).ok();

    if let Some(ref mut s) = stmt {
        if let Ok(rows) = s.query_map(params![task.id], |row| {
            Ok((
                row.get::<_, f64>(0).unwrap_or(0.0),
                row.get::<_, String>(1).unwrap_or_default(),
                row.get::<_, String>(2).unwrap_or_default(),
                row.get::<_, Option<String>>(3).unwrap_or(None),
                row.get::<_, Option<String>>(4).unwrap_or(None),
            ))
        }) {
            for row in rows.flatten() {
                memory.push_str(&format!(
                    "Previous review (score: {:.1}, verdict: {}):\n{}\n",
                    row.0, row.1, row.2
                ));
                if let Some(issues) = row.3 {
                    memory.push_str(&format!("Issues: {}\n", issues));
                }
                if let Some(suggestions) = row.4 {
                    memory.push_str(&format!("Suggestions: {}\n", suggestions));
                }
                memory.push('\n');
            }
        }
    }

    // Previous error message
    if let Some(ref err) = task.error_message {
        memory.push_str(&format!("Previous error: {}\n\n", err));
    }

    // Previous output (truncated)
    if let Some(ref result) = task.result {
        let truncated = if result.len() > 2000 {
            &result[..2000]
        } else {
            result
        };
        memory.push_str(&format!("Previous output (truncated):\n{}\n\n", truncated));
    }

    // User revision prompt
    if let Some(ref revision) = task.revision_prompt {
        memory.push_str(&format!("User revision instructions:\n{}\n", revision));
    }

    memory
}

/// Update task to passed status with result data.
async fn update_task_success(task: &AgentTask, result: &TaskRunResult, db: &Arc<Mutex<Database>>) {
    let db_lock = db.lock().await;
    let _ = db_lock.conn.execute(
        "UPDATE agentTask SET status = 'passed', result = ?2, costUSD = ?3, durationMs = ?4, sessionId = ?5, completedAt = datetime('now'), updatedAt = datetime('now') WHERE id = ?1",
        params![task.id, result.output, result.cost_usd, result.duration_ms, result.session_id],
    );
}

/// Record cost tracking entry.
async fn record_cost(task: &AgentTask, result: &TaskRunResult, db: &Arc<Mutex<Database>>) {
    if result.cost_usd.is_none() && result.input_tokens.is_none() {
        return;
    }

    let db_lock = db.lock().await;
    let id = uuid::Uuid::new_v4().to_string();
    let _ = db_lock.conn.execute(
        "INSERT INTO costTracking (id, projectId, taskId, agentType, inputTokens, outputTokens, costUSD, model, sessionId, backend, createdAt)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, datetime('now'))",
        params![
            id,
            task.project_id,
            task.id,
            task.agent_type,
            result.input_tokens.unwrap_or(0),
            result.output_tokens.unwrap_or(0),
            result.cost_usd.unwrap_or(0.0),
            result.model.as_deref().unwrap_or("unknown"),
            result.session_id,
            result.backend_type,
        ],
    );
}

/// Agent-specific completion handlers.
async fn handle_agent_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
    app_handle: Option<&tauri::AppHandle>,
) {
    let agent_type = AgentType::from_str(&task.agent_type);

    match agent_type {
        AgentType::Analyzer => handle_analyzer_completion(task, result, db).await,
        AgentType::Coder => handle_coder_completion(task, result, db).await,
        AgentType::Reviewer => handle_reviewer_completion(task, result, db, app_handle).await,
        AgentType::Designer | AgentType::ImageGenerator | AgentType::VideoEditor => {
            handle_creative_completion(task, result, db).await;
        }
        AgentType::Publisher => handle_publisher_completion(task, result, db).await,
        AgentType::ContentWriter => handle_content_writer_completion(task, result, db).await,
        _ => {} // Tester, DevOps, Monitor, Planner — no special handling
    }
}

/// Analyzer: parse JSON output → create features + tasks in DB.
async fn handle_analyzer_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
) {
    let json = match extract_json(&result.output) {
        Some(j) => j,
        None => {
            log::warn!("Analyzer output is not valid JSON for task {}", task.id);
            return;
        }
    };

    let features = match json.get("features").and_then(|f| f.as_array()) {
        Some(f) => f,
        None => {
            log::warn!("Analyzer output missing 'features' array");
            return;
        }
    };

    let db_lock = db.lock().await;

    for feature_json in features {
        let feature_id = uuid::Uuid::new_v4().to_string();
        let name = feature_json.get("name").and_then(|n| n.as_str()).unwrap_or("Unnamed Feature");
        let description = feature_json.get("description").and_then(|d| d.as_str()).unwrap_or("");
        let priority = feature_json.get("priority").and_then(|p| p.as_i64()).unwrap_or(5) as i32;

        let _ = db_lock.conn.execute(
            "INSERT INTO feature (id, projectId, name, description, priority, status, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, 'pending', datetime('now'), datetime('now'))",
            params![feature_id, task.project_id, name, description, priority],
        );

        if let Some(tasks) = feature_json.get("tasks").and_then(|t| t.as_array()) {
            let mut task_ids: Vec<(String, String)> = Vec::new(); // (title, id) for dependency resolution

            for task_json in tasks {
                let task_id = uuid::Uuid::new_v4().to_string();
                let title = task_json.get("title").and_then(|t| t.as_str()).unwrap_or("Unnamed Task");
                let desc = task_json.get("description").and_then(|d| d.as_str()).unwrap_or("");
                let agent = task_json.get("agentType").and_then(|a| a.as_str()).unwrap_or("coder");
                let prio = task_json.get("priority").and_then(|p| p.as_i64()).unwrap_or(5) as i32;
                let skill_persona = task_json.get("skillPersona").and_then(|s| s.as_str());
                let complexity = task_json.get("estimatedComplexity").and_then(|c| c.as_str());
                let acceptance = task_json.get("acceptanceCriteria").and_then(|a| a.as_array());
                let files = task_json.get("filesToCreate").and_then(|f| f.as_array());

                // Build enriched description with skill, criteria, files
                let mut enriched = desc.to_string();
                if let Some(persona) = skill_persona {
                    enriched.push_str(&format!("\n\n--- Required Skill ---\n  {}", persona));
                }
                if let Some(c) = complexity {
                    enriched.push_str(&format!("\n[Complexity: {}]", c));
                }
                if let Some(criteria) = acceptance {
                    enriched.push_str("\n\n--- Acceptance Criteria ---");
                    for (i, c) in criteria.iter().enumerate() {
                        if let Some(s) = c.as_str() {
                            enriched.push_str(&format!("\n  {}. {}", i + 1, s));
                        }
                    }
                }
                if let Some(file_list) = files {
                    enriched.push_str("\n\n--- Files to Create/Modify ---");
                    for f in file_list {
                        if let Some(s) = f.as_str() {
                            enriched.push_str(&format!("\n  - {}", s));
                        }
                    }
                }

                let _ = db_lock.conn.execute(
                    "INSERT INTO agentTask (id, projectId, featureId, agentType, title, description, priority, status, retryCount, maxRetries, skillPersona, createdAt, updatedAt)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'queued', 0, 3, ?8, datetime('now'), datetime('now'))",
                    params![task_id, task.project_id, feature_id, agent, title, enriched, prio, skill_persona],
                );

                task_ids.push((title.to_string(), task_id.clone()));

                // Handle dependencies
                if let Some(deps) = task_json.get("dependencies").and_then(|d| d.as_array()) {
                    for dep in deps {
                        if let Some(dep_title) = dep.as_str() {
                            // Find the task ID by title
                            if let Some((_, dep_id)) = task_ids.iter().find(|(t, _)| t == dep_title) {
                                let _ = db_lock.conn.execute(
                                    "INSERT OR IGNORE INTO taskDependency (taskId, dependsOnTaskId) VALUES (?1, ?2)",
                                    params![task_id, dep_id],
                                );
                            }
                        }
                    }
                }
            }
        }

        log::info!("Created feature '{}' with tasks for project {}", name, task.project_id);
    }

    // Update project status to in_progress
    let _ = db_lock.conn.execute(
        "UPDATE project SET status = 'in_progress', updatedAt = datetime('now') WHERE id = ?1",
        params![task.project_id],
    );
}

/// Coder: extract branchName and prNumber from result, update task.
async fn handle_coder_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
) {
    // Setup feature branch if not already done
    let dir = {
        let db_lock = db.lock().await;
        let d: Option<String> = db_lock.conn.query_row(
            "SELECT directoryPath FROM project WHERE id = ?1",
            [&task.project_id],
            |row| row.get(0),
        ).ok();
        d.filter(|d| !d.is_empty())
    };

    if let Some(dir) = dir {
        // Try to extract branch name from output
        if let Some(json) = extract_json(&result.output) {
            let branch = json.get("branchName").and_then(|b| b.as_str());
            let pr_number = json.get("prNumber").and_then(|p| p.as_i64()).map(|p| p as i32);

            if branch.is_some() || pr_number.is_some() {
                let db_lock = db.lock().await;
                let _ = db_lock.conn.execute(
                    "UPDATE agentTask SET branchName = COALESCE(?2, branchName), prNumber = COALESCE(?3, prNumber), updatedAt = datetime('now') WHERE id = ?1",
                    params![task.id, branch, pr_number],
                );
            }
        }

        // If no branch was set, try setting up one and committing
        let task_branch = {
            let db_lock = db.lock().await;
            db_lock.conn.query_row(
                "SELECT branchName FROM agentTask WHERE id = ?1",
                [&task.id],
                |row| row.get::<_, Option<String>>(0),
            ).ok().flatten()
        };

        if task_branch.is_none() {
            if let Ok(branch) = GitBranchManager::setup_feature_branch(&dir, &task.id, &task.title).await {
                let db_lock = db.lock().await;
                let _ = db_lock.conn.execute(
                    "UPDATE agentTask SET branchName = ?2, updatedAt = datetime('now') WHERE id = ?1",
                    params![task.id, branch],
                );
            }
        }

        // Queue a review task for the coder's work
        let review_task_id = uuid::Uuid::new_v4().to_string();
        let db_lock = db.lock().await;
        let _ = db_lock.conn.execute(
            "INSERT INTO agentTask (id, projectId, featureId, agentType, title, description, priority, status, retryCount, maxRetries, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, 'reviewer', ?4, ?5, ?6, 'queued', 0, 3, datetime('now'), datetime('now'))",
            params![
                review_task_id,
                task.project_id,
                task.feature_id,
                format!("Review: {}", task.title),
                format!("Review the code changes for task: {}", task.description),
                task.priority,
            ],
        );
        // Add dependency: review depends on coder
        let _ = db_lock.conn.execute(
            "INSERT OR IGNORE INTO taskDependency (taskId, dependsOnTaskId) VALUES (?1, ?2)",
            params![review_task_id, task.id],
        );
    }
}

/// Reviewer: parse score/verdict, create Review record, update task status.
async fn handle_reviewer_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
    app_handle: Option<&tauri::AppHandle>,
) {
    let json = match extract_json(&result.output) {
        Some(j) => j,
        None => {
            log::warn!("Reviewer output is not valid JSON for task {}", task.id);
            return;
        }
    };

    let score = json.get("score").and_then(|s| s.as_f64()).unwrap_or(0.0);
    let _verdict_str = json.get("verdict").and_then(|v| v.as_str()).unwrap_or("fail");
    let summary = json.get("summary").and_then(|s| s.as_str()).unwrap_or("");
    let issues = json.get("issues").and_then(|i| i.as_str());
    let suggestions = json.get("suggestions").and_then(|s| s.as_str());
    let security_notes = json.get("securityNotes").and_then(|s| s.as_str());

    // Determine verdict: >= 7.0 PASS, 5.0-6.9 NEEDS_REVISION, < 5.0 FAIL
    let verdict = if score >= 7.0 {
        "pass"
    } else if score >= 5.0 {
        "needsRevision"
    } else {
        "fail"
    };

    let review_id = uuid::Uuid::new_v4().to_string();
    let db_lock = db.lock().await;

    // Insert review record
    let _ = db_lock.conn.execute(
        "INSERT INTO review (id, taskId, score, verdict, summary, issues, suggestions, securityNotes, sessionId, costUSD, isApproved, createdAt)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 0, datetime('now'))",
        params![
            review_id,
            task.id,
            score,
            verdict,
            summary,
            issues,
            suggestions,
            security_notes,
            result.session_id,
            result.cost_usd,
        ],
    );

    // Find the coder task that this review is for (the dependency)
    let coder_task_id: Option<String> = db_lock.conn.query_row(
        "SELECT dependsOnTaskId FROM taskDependency WHERE taskId = ?1 LIMIT 1",
        params![task.id],
        |row| row.get(0),
    ).ok();

    if let Some(coder_id) = coder_task_id {
        match verdict {
            "pass" => {
                log::info!("Review passed (score: {:.1}) for coder task {}", score, coder_id);
                // Merge feature branch into dev
                // The git completion handler will handle this
            }
            "needsRevision" => {
                log::info!("Review needs revision (score: {:.1}) for coder task {}", score, coder_id);
                // Requeue the coder task with revision prompt
                let _ = db_lock.conn.execute(
                    "UPDATE agentTask SET status = 'needs_revision', revisionPrompt = ?2, updatedAt = datetime('now') WHERE id = ?1",
                    params![coder_id, format!("Review feedback (score {:.1}):\n{}\n\nIssues: {}\nSuggestions: {}", score, summary, issues.unwrap_or(""), suggestions.unwrap_or(""))],
                );
            }
            _ => {
                log::info!("Review failed (score: {:.1}) for coder task {}", score, coder_id);
                let _ = db_lock.conn.execute(
                    "UPDATE agentTask SET status = 'failed', errorMessage = ?2, updatedAt = datetime('now') WHERE id = ?1",
                    params![coder_id, format!("Review failed with score {:.1}: {}", score, summary)],
                );
            }
        }
    }

    // Emit review event
    if let Some(handle) = app_handle {
        let _ = handle.emit("review-completed", serde_json::json!({
            "reviewId": review_id,
            "taskId": task.id,
            "score": score,
            "verdict": verdict,
        }));
    }
}

/// Creative agents: parse {"assets": [...]} from output, save to DB.
async fn handle_creative_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
) {
    let json = match extract_json(&result.output) {
        Some(j) => j,
        None => {
            // Not JSON — save raw output as a text asset
            save_raw_asset(task, &result.output, db).await;
            return;
        }
    };

    let assets = match json.get("assets").and_then(|a| a.as_array()) {
        Some(a) => a,
        None => {
            save_raw_asset(task, &result.output, db).await;
            return;
        }
    };

    let db_lock = db.lock().await;
    for asset_json in assets {
        let asset_id = uuid::Uuid::new_v4().to_string();
        let name = asset_json.get("name").and_then(|n| n.as_str()).unwrap_or("Untitled");
        let description = asset_json.get("description").and_then(|d| d.as_str()).unwrap_or("");
        let file_path = asset_json.get("filePath").and_then(|f| f.as_str()).unwrap_or("");
        let asset_type = asset_json.get("type").and_then(|t| t.as_str()).unwrap_or("document");
        let mime_type = asset_json.get("mimeType").and_then(|m| m.as_str());
        let source_url = asset_json.get("sourceUrl").and_then(|u| u.as_str());

        let _ = db_lock.conn.execute(
            "INSERT INTO generatedAsset (id, projectId, taskId, agentType, assetType, name, description, filePath, mimeType, sourceUrl, status, version, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'generated', 1, datetime('now'), datetime('now'))",
            params![
                asset_id, task.project_id, task.id, task.agent_type,
                asset_type, name, description, file_path, mime_type, source_url,
            ],
        );

        log::info!("Saved asset '{}' for task {}", name, task.id);
    }
}

/// Save raw text output as a document asset.
async fn save_raw_asset(task: &AgentTask, output: &str, db: &Arc<Mutex<Database>>) {
    if output.is_empty() {
        return;
    }

    let db_lock = db.lock().await;
    let asset_id = uuid::Uuid::new_v4().to_string();
    let _ = db_lock.conn.execute(
        "INSERT INTO generatedAsset (id, projectId, taskId, agentType, assetType, name, description, filePath, status, version, createdAt, updatedAt)
         VALUES (?1, ?2, ?3, ?4, 'document', 'Raw Output', ?5, '', 'generated', 1, datetime('now'), datetime('now'))",
        params![asset_id, task.project_id, task.id, task.agent_type, &output[..output.len().min(500)]],
    );
}

/// Publisher: parse {"publications": [...]} from output.
async fn handle_publisher_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
) {
    let json = match extract_json(&result.output) {
        Some(j) => j,
        None => return,
    };

    let publications = match json.get("publications").and_then(|p| p.as_array()) {
        Some(p) => p,
        None => return,
    };

    let db_lock = db.lock().await;
    for pub_json in publications {
        let pub_id = uuid::Uuid::new_v4().to_string();
        let channel_id = pub_json.get("channelId").and_then(|c| c.as_str()).unwrap_or("");
        let external_id = pub_json.get("externalId").and_then(|e| e.as_str());
        let published_url = pub_json.get("publishedUrl").and_then(|u| u.as_str());
        let status = pub_json.get("status").and_then(|s| s.as_str()).unwrap_or("published");

        let _ = db_lock.conn.execute(
            "INSERT INTO publication (id, assetId, projectId, channelId, status, externalId, publishedUrl, publishedAt, exportFormat, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, datetime('now'), 'markdown', datetime('now'), datetime('now'))",
            params![
                pub_id, task.id, task.project_id, channel_id,
                status, external_id, published_url,
            ],
        );

        log::info!("Recorded publication for channel {} (task {})", channel_id, task.id);
    }
}

/// Content writer: parse output with 3-tier fallback (JSON → YAML front matter → raw markdown),
/// save as document assets, queue image generation tasks for placeholders, queue publisher.
async fn handle_content_writer_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
) {
    let parsed = parse_content_writer_output(&result.output, task);
    if parsed.assets.is_empty() {
        log::warn!("ContentWriter produced no parseable output for task {}", task.id);
        return;
    }

    let db_lock = db.lock().await;

    for asset in &parsed.assets {
        let asset_id = uuid::Uuid::new_v4().to_string();
        let file_name = if asset.name.contains('.') {
            asset.name.clone()
        } else {
            format!("{}.md", asset.name)
        };

        // Save content to file
        let project_name: Option<String> = db_lock.conn.query_row(
            "SELECT name FROM project WHERE id = ?1",
            [&task.project_id],
            |row| row.get(0),
        ).ok();

        let project_name = project_name.unwrap_or_else(|| "unknown".to_string());
        let home = dirs::home_dir().unwrap_or_default();
        let assets_dir = home.join("CreedFlow").join("projects").join(&project_name).join("assets");
        let _ = std::fs::create_dir_all(&assets_dir);
        let file_path = assets_dir.join(&file_name);
        let _ = std::fs::write(&file_path, &asset.content);

        let file_size = asset.content.len() as i64;
        let file_path_str = file_path.to_string_lossy().to_string();

        // Compute checksum
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(asset.content.as_bytes());
        let checksum = hex::encode(hasher.finalize());

        // Build metadata JSON if available
        let metadata_json = parsed.metadata.as_ref().map(|m| {
            serde_json::to_string(m).unwrap_or_default()
        });

        let _ = db_lock.conn.execute(
            "INSERT INTO generatedAsset (id, projectId, taskId, agentType, assetType, name, description, filePath, mimeType, fileSize, metadata, checksum, status, version, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, 'document', ?5, '', ?6, 'text/markdown', ?7, ?8, ?9, 'generated', 1, datetime('now'), datetime('now'))",
            params![
                asset_id, task.project_id, task.id, task.agent_type,
                file_name, file_path_str, file_size, metadata_json, checksum,
            ],
        );

        log::info!("Saved content document '{}' for task {} ({})", file_name, task.id, parsed.parse_method);
    }

    // Scan for image placeholders and queue ImageGenerator tasks
    for asset in &parsed.assets {
        scan_and_queue_images(&asset.content, task, &db_lock);
    }

    // Generate format variants (txt, html, pdf) from saved markdown
    generate_content_format_variants(task, &db_lock);

    // Queue publisher task if publishing channels exist
    let has_channels: bool = db_lock.conn.query_row(
        "SELECT COUNT(*) FROM publishingChannel WHERE isEnabled = 1",
        [],
        |row| row.get::<_, i32>(0),
    ).unwrap_or(0) > 0;

    if has_channels {
        let publish_task_id = uuid::Uuid::new_v4().to_string();
        let _ = db_lock.conn.execute(
            "INSERT INTO agentTask (id, projectId, featureId, agentType, title, description, priority, status, retryCount, maxRetries, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, 'publisher', ?4, ?5, ?6, 'queued', 0, 3, datetime('now'), datetime('now'))",
            params![
                publish_task_id, task.project_id, task.feature_id,
                format!("Publish: {}", task.title),
                format!("Select publishing channels and schedule publication for: {}", task.title),
                task.priority,
            ],
        );
        let _ = db_lock.conn.execute(
            "INSERT OR IGNORE INTO taskDependency (taskId, dependsOnTaskId) VALUES (?1, ?2)",
            params![publish_task_id, task.id],
        );
    }
}

/// Parsed output from ContentWriter agent.
struct ContentWriterParsedOutput {
    assets: Vec<ContentDocumentAsset>,
    metadata: Option<serde_json::Value>,
    parse_method: String,
}

struct ContentDocumentAsset {
    name: String,
    content: String,
}

/// Parse ContentWriter output with 3-tier fallback: JSON → YAML front matter → raw markdown.
fn parse_content_writer_output(output: &str, task: &AgentTask) -> ContentWriterParsedOutput {
    if output.is_empty() {
        return ContentWriterParsedOutput { assets: vec![], metadata: None, parse_method: "empty".to_string() };
    }

    let sanitized_title = sanitize_title_for_file(&task.title);

    // Tier 1: Try JSON {"assets": [...]} format
    if let Some(json) = extract_json(output) {
        if let Some(assets_arr) = json.get("assets").and_then(|a| a.as_array()) {
            let documents: Vec<ContentDocumentAsset> = assets_arr.iter().filter_map(|item| {
                let content = item.get("content").and_then(|c| c.as_str())?;
                if content.is_empty() { return None; }
                let name = item.get("name")
                    .and_then(|n| n.as_str())
                    .unwrap_or(&sanitized_title)
                    .to_string();
                Some(ContentDocumentAsset { name, content: content.to_string() })
            }).collect();

            if !documents.is_empty() {
                return ContentWriterParsedOutput {
                    assets: documents,
                    metadata: None,
                    parse_method: "json".to_string(),
                };
            }
        }
    }

    // Tier 2: Try YAML front matter (---\n...\n---\ncontent)
    if let Some(result) = parse_yaml_front_matter(output, &sanitized_title) {
        return result;
    }

    // Tier 3: Raw markdown fallback
    let name = format!("{}.md", sanitized_title);
    ContentWriterParsedOutput {
        assets: vec![ContentDocumentAsset { name, content: output.trim().to_string() }],
        metadata: None,
        parse_method: "raw".to_string(),
    }
}

/// Parse YAML front matter from text. Returns None if no front matter found.
fn parse_yaml_front_matter(text: &str, default_name: &str) -> Option<ContentWriterParsedOutput> {
    let trimmed = text.trim();
    if !trimmed.starts_with("---") {
        return None;
    }

    let after_first = &trimmed[3..].trim_start_matches('\n');
    let closing_pos = after_first.find("\n---")?;

    let yaml_block = &after_first[..closing_pos];
    let markdown_body = after_first[closing_pos + 4..].trim();

    if markdown_body.is_empty() {
        return None;
    }

    // Parse simple YAML key-value pairs into a JSON object
    let mut metadata = serde_json::Map::new();
    let mut name: Option<String> = None;

    for line in yaml_block.lines() {
        let parts: Vec<&str> = line.splitn(2, ':').collect();
        if parts.len() != 2 { continue; }
        let key = parts[0].trim();
        let mut value = parts[1].trim().to_string();

        // Strip surrounding quotes
        if (value.starts_with('"') && value.ends_with('"')) ||
           (value.starts_with('\'') && value.ends_with('\'')) {
            value = value[1..value.len()-1].to_string();
        }

        // Parse arrays like ["tag1", "tag2"]
        if value.starts_with('[') && value.ends_with(']') {
            let inner = &value[1..value.len()-1];
            let items: Vec<serde_json::Value> = inner.split(',')
                .map(|s| {
                    let s = s.trim().trim_matches('"').trim_matches('\'');
                    serde_json::Value::String(s.to_string())
                })
                .collect();
            metadata.insert(key.to_string(), serde_json::Value::Array(items));
        } else {
            metadata.insert(key.to_string(), serde_json::Value::String(value.clone()));
        }

        if key == "name" {
            name = Some(value);
        } else if key == "title" && name.is_none() {
            name = Some(format!("{}.md", sanitize_title_for_file(&value)));
        }
    }

    let file_name = name.unwrap_or_else(|| format!("{}.md", default_name));

    // Add word count
    let word_count = markdown_body.split_whitespace().count();
    metadata.insert("wordCount".to_string(), serde_json::Value::Number(word_count.into()));
    metadata.entry("author".to_string())
        .or_insert(serde_json::Value::String("CreedFlow".to_string()));

    Some(ContentWriterParsedOutput {
        assets: vec![ContentDocumentAsset { name: file_name, content: markdown_body.to_string() }],
        metadata: Some(serde_json::Value::Object(metadata)),
        parse_method: "yaml".to_string(),
    })
}

/// Scan content for creedflow:image:slug placeholders and queue ImageGenerator tasks.
fn scan_and_queue_images(content: &str, task: &AgentTask, db: &Database) {
    let re = match regex::Regex::new(r"!\[([^\]]*)\]\(creedflow:image:([a-z0-9-]+)\)") {
        Ok(r) => r,
        Err(_) => return,
    };

    for cap in re.captures_iter(content) {
        let description = cap.get(1).map(|m| m.as_str()).unwrap_or("");
        let slug = cap.get(2).map(|m| m.as_str()).unwrap_or("");

        let image_task_id = uuid::Uuid::new_v4().to_string();
        let _ = db.conn.execute(
            "INSERT INTO agentTask (id, projectId, featureId, agentType, title, description, priority, status, retryCount, maxRetries, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, 'imageGenerator', ?4, ?5, ?6, 'queued', 0, 3, datetime('now'), datetime('now'))",
            params![
                image_task_id, task.project_id, task.feature_id,
                format!("Generate image: {}", slug),
                format!("Generate an image for content placeholder. Description: {}. Slug: {}. Parent content task: {}", description, slug, task.id),
                task.priority,
            ],
        );
        let _ = db.conn.execute(
            "INSERT OR IGNORE INTO taskDependency (taskId, dependsOnTaskId) VALUES (?1, ?2)",
            params![image_task_id, task.id],
        );

        log::info!("Queued image generation for slug '{}' (task {})", slug, task.id);
    }
}

/// Generate format variants (txt, html, pdf) from markdown document assets.
fn generate_content_format_variants(task: &AgentTask, db: &Database) {
    use crate::services::content_exporter::ContentExporter;

    // Find all markdown assets for this task
    let mut stmt = match db.conn.prepare(
        "SELECT id, name, filePath FROM generatedAsset WHERE taskId = ?1 AND assetType = 'document' AND mimeType = 'text/markdown'"
    ) {
        Ok(s) => s,
        Err(_) => return,
    };

    let assets: Vec<(String, String, String)> = stmt.query_map(params![task.id], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
        ))
    }).ok().map(|rows| rows.flatten().collect()).unwrap_or_default();

    for (_asset_id, name, file_path) in &assets {
        let markdown = match std::fs::read_to_string(file_path) {
            Ok(m) => m,
            Err(_) => continue,
        };

        let base_name = name.trim_end_matches(".md");
        let dir = std::path::Path::new(file_path).parent().unwrap_or(std::path::Path::new("."));

        // .txt variant
        let plaintext = ContentExporter::markdown_to_plaintext(&markdown);
        let txt_path = dir.join(format!("{}.txt", base_name));
        if std::fs::write(&txt_path, &plaintext).is_ok() {
            let txt_id = uuid::Uuid::new_v4().to_string();
            let _ = db.conn.execute(
                "INSERT INTO generatedAsset (id, projectId, taskId, agentType, assetType, name, description, filePath, mimeType, fileSize, status, version, createdAt, updatedAt)
                 VALUES (?1, ?2, ?3, ?4, 'document', ?5, '', ?6, 'text/plain', ?7, 'generated', 1, datetime('now'), datetime('now'))",
                params![txt_id, task.project_id, task.id, task.agent_type,
                    format!("{}.txt", base_name), txt_path.to_string_lossy().to_string(), plaintext.len() as i64],
            );
        }

        // .html variant
        let html = ContentExporter::markdown_to_html(&markdown);
        let html_path = dir.join(format!("{}.html", base_name));
        if std::fs::write(&html_path, &html).is_ok() {
            let html_id = uuid::Uuid::new_v4().to_string();
            let _ = db.conn.execute(
                "INSERT INTO generatedAsset (id, projectId, taskId, agentType, assetType, name, description, filePath, mimeType, fileSize, status, version, createdAt, updatedAt)
                 VALUES (?1, ?2, ?3, ?4, 'document', ?5, '', ?6, 'text/html', ?7, 'generated', 1, datetime('now'), datetime('now'))",
                params![html_id, task.project_id, task.id, task.agent_type,
                    format!("{}.html", base_name), html_path.to_string_lossy().to_string(), html.len() as i64],
            );
        }

        // .pdf variant
        match ContentExporter::markdown_to_pdf(&markdown) {
            Ok(pdf_bytes) => {
                let pdf_path = dir.join(format!("{}.pdf", base_name));
                if std::fs::write(&pdf_path, &pdf_bytes).is_ok() {
                    let pdf_id = uuid::Uuid::new_v4().to_string();
                    let _ = db.conn.execute(
                        "INSERT INTO generatedAsset (id, projectId, taskId, agentType, assetType, name, description, filePath, mimeType, fileSize, status, version, createdAt, updatedAt)
                         VALUES (?1, ?2, ?3, ?4, 'document', ?5, '', ?6, 'application/pdf', ?7, 'generated', 1, datetime('now'), datetime('now'))",
                        params![pdf_id, task.project_id, task.id, task.agent_type,
                            format!("{}.pdf", base_name), pdf_path.to_string_lossy().to_string(), pdf_bytes.len() as i64],
                    );
                }
            }
            Err(e) => log::warn!("Failed to generate PDF for {}: {}", name, e),
        }

        // .docx variant
        match ContentExporter::markdown_to_docx(&markdown) {
            Ok(docx_bytes) => {
                let docx_path = dir.join(format!("{}.docx", base_name));
                if std::fs::write(&docx_path, &docx_bytes).is_ok() {
                    let docx_id = uuid::Uuid::new_v4().to_string();
                    let _ = db.conn.execute(
                        "INSERT INTO generatedAsset (id, projectId, taskId, agentType, assetType, name, description, filePath, mimeType, fileSize, status, version, createdAt, updatedAt)
                         VALUES (?1, ?2, ?3, ?4, 'document', ?5, '', ?6, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', ?7, 'generated', 1, datetime('now'), datetime('now'))",
                        params![docx_id, task.project_id, task.id, task.agent_type,
                            format!("{}.docx", base_name), docx_path.to_string_lossy().to_string(), docx_bytes.len() as i64],
                    );
                }
            }
            Err(e) => log::warn!("Failed to generate DOCX for {}: {}", name, e),
        }
    }
}

fn sanitize_title_for_file(title: &str) -> String {
    title
        .to_lowercase()
        .replace(' ', "-")
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-')
        .take(30)
        .collect()
}

/// Git completion pipeline: auto-commit, merge, promote.
async fn handle_git_completion(
    task: &AgentTask,
    db: &Arc<Mutex<Database>>,
    app_handle: Option<&tauri::AppHandle>,
) {
    let dir = {
        let db_lock = db.lock().await;
        let d: Option<String> = db_lock.conn.query_row(
            "SELECT directoryPath FROM project WHERE id = ?1",
            [&task.project_id],
            |row| row.get(0),
        ).ok();
        d.filter(|d| !d.is_empty())
    };

    let dir = match dir {
        Some(d) => d,
        None => return,
    };

    // 1. Auto-commit for non-coder tasks
    if task.agent_type != "coder" {
        match GitBranchManager::auto_commit_if_needed(&dir, &task.id, &task.title, &task.agent_type).await {
            Ok(Some(hash)) => log::info!("Auto-committed {} for task {}", hash, task.id),
            Ok(None) => {}
            Err(e) => log::warn!("Auto-commit failed for task {}: {}", task.id, e),
        }
    }

    // 2. Merge feature branch into dev
    let branch_name = {
        let db_lock = db.lock().await;
        db_lock.conn.query_row(
            "SELECT branchName FROM agentTask WHERE id = ?1",
            [&task.id],
            |row| row.get::<_, Option<String>>(0),
        ).ok().flatten()
    };

    if let Some(branch) = branch_name {
        let protected = ["dev", "staging", "main", "master", "develop"];
        if !protected.contains(&branch.as_str()) {
            match GitBranchManager::merge_feature_to_dev(&dir, &branch).await {
                Ok(()) => log::info!("Merged {} into dev", branch),
                Err(e) => log::warn!("Failed to merge {} into dev: {}", branch, e),
            }
        }
    }

    // 3. Check feature completion → promote
    if let Some(ref feature_id) = task.feature_id {
        let all_passed = {
            let db_lock = db.lock().await;
            let count: i32 = db_lock.conn.query_row(
                "SELECT COUNT(*) FROM agentTask
                 WHERE featureId = ?1 AND archivedAt IS NULL AND status != 'passed' AND status != 'cancelled'",
                params![feature_id],
                |row| row.get(0),
            ).unwrap_or(1);
            count == 0
        };

        if all_passed {
            log::info!("All tasks for feature {} passed — promoting dev to staging", feature_id);
            match GitBranchManager::promote_dev_to_staging(&dir).await {
                Ok(pr_url) => log::info!("Created staging PR: {}", pr_url),
                Err(e) => log::warn!("Failed to promote dev to staging: {}", e),
            }
        }
    }

    // Emit completion event
    if let Some(handle) = app_handle {
        let _ = handle.emit("task-status-changed", serde_json::json!({
            "taskId": task.id,
            "status": "passed",
            "agentType": task.agent_type,
        }));
    }
}

/// Returns true if the agent type is a creative agent that requires MCP services
fn is_creative_agent(agent_type: &AgentType) -> bool {
    matches!(
        agent_type,
        AgentType::ImageGenerator | AgentType::VideoEditor | AgentType::Designer
    )
}
