use crate::backends::{
    build_attachment_prompt, BackendPreferences, BackendRouter, CliBackend, OutputEvent, TaskInput,
    claude::ClaudeBackend,
    codex::CodexBackend,
    gemini::GeminiBackend,
    ollama::OllamaBackend,
    lmstudio::LMStudioBackend,
    llamacpp::LlamaCppBackend,
    mlx::MLXBackend,
    opencode::OpenCodeBackend,
};
use crate::db::models::{AppSettings, ChatAttachment, ProjectMessage};
use crate::state::AppState;
use tauri::{Emitter, Manager, State};
use uuid::Uuid;

fn load_settings(app_handle: &tauri::AppHandle) -> AppSettings {
    let dir = app_handle.path().app_data_dir().ok();
    let path = dir.map(|d| d.join("settings.json"));
    path.and_then(|p| std::fs::read_to_string(&p).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

#[tauri::command]
pub async fn send_chat_message(
    state: State<'_, AppState>,
    project_id: String,
    content: String,
    role: String,
    attachments: Option<Vec<ChatAttachment>>,
) -> Result<ProjectMessage, String> {
    let now = chrono::Utc::now()
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string();

    let attachments_json = attachments
        .as_ref()
        .filter(|a| !a.is_empty())
        .and_then(|a| serde_json::to_string(a).ok());

    let msg = ProjectMessage {
        id: Uuid::new_v4().to_string(),
        project_id,
        role,
        content,
        backend: None,
        cost_usd: None,
        duration_ms: None,
        metadata: None,
        attachments: attachments_json,
        created_at: now,
    };
    let db = state.db.lock().await;
    ProjectMessage::insert(&db.conn, &msg).map_err(|e| e.to_string())?;
    Ok(msg)
}

#[tauri::command]
pub async fn stream_chat_response(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    project_id: String,
    content: String,
    attachments: Vec<ChatAttachment>,
) -> Result<String, String> {
    // 1. Create a BackendRouter with all backends
    let backends: Vec<Box<dyn CliBackend>> = vec![
        Box::new(ClaudeBackend::new()),
        Box::new(CodexBackend::new()),
        Box::new(GeminiBackend::new()),
        Box::new(OpenCodeBackend::new()),
        Box::new(OllamaBackend::new()),
        Box::new(LMStudioBackend::new()),
        Box::new(LlamaCppBackend::new()),
        Box::new(MLXBackend::new()),
    ];
    let router = BackendRouter::new(backends);

    // Load enabled backends from settings
    {
        let settings = load_settings(&app);
        for bt in [
            "claude", "codex", "gemini", "opencode", "ollama", "lmstudio", "llamacpp", "mlx",
        ] {
            let enabled = match bt {
                "claude" => settings.claude_enabled,
                "codex" => settings.codex_enabled,
                "gemini" => settings.gemini_enabled,
                "opencode" => settings.opencode_enabled,
                "ollama" => settings.ollama_enabled,
                "lmstudio" => settings.lm_studio_enabled,
                "llamacpp" => settings.llama_cpp_enabled,
                "mlx" => settings.mlx_enabled,
                _ => false,
            };
            router.set_enabled(bt, enabled);
        }
    }

    // 2. Select a backend
    let backend = router
        .select_backend(&BackendPreferences::AnyBackend)
        .await
        .ok_or("No AI backend available. Enable at least one backend in Settings.")?;

    let backend_type = backend.backend_type().as_str().to_string();

    // 3. Load conversation history (last 30 messages)
    let history = {
        let db = state.db.lock().await;
        ProjectMessage::list_by_project(&db.conn, &project_id)
            .map_err(|e| e.to_string())?
    };
    let recent: Vec<&ProjectMessage> = if history.len() > 30 {
        history.iter().rev().take(30).collect::<Vec<_>>().into_iter().rev().collect()
    } else {
        history.iter().collect()
    };

    // 4. Load project info
    let project_summary = {
        let db = state.db.lock().await;
        db.conn
            .query_row(
                "SELECT name, description, techStack, projectType FROM project WHERE id = ?1",
                [&project_id],
                |row| {
                    let name: String = row.get(0)?;
                    let desc: String = row.get(1)?;
                    let tech: String = row.get(2)?;
                    let ptype: String = row.get(3)?;
                    Ok(format!(
                        "Project: {} | Type: {} | Tech: {} | Description: {}",
                        name, ptype, tech, desc
                    ))
                },
            )
            .unwrap_or_else(|_| "Project info not available".to_string())
    };

    let working_dir = {
        let db = state.db.lock().await;
        db.conn
            .query_row(
                "SELECT directoryPath FROM project WHERE id = ?1",
                [&project_id],
                |row| row.get::<_, String>(0),
            )
            .ok()
            .filter(|d| !d.is_empty())
            .unwrap_or_else(|| ".".to_string())
    };

    // 5. Build the full prompt
    let mut prompt_parts = Vec::new();

    prompt_parts.push("You are a project planning assistant for CreedFlow. Help the user plan features and tasks for their project.".to_string());
    prompt_parts.push(String::new());
    prompt_parts.push(format!("## Project\n{}", project_summary));

    if !recent.is_empty() {
        prompt_parts.push(String::new());
        prompt_parts.push("## Recent Conversation".to_string());
        for msg in &recent {
            let label = match msg.role.as_str() {
                "user" => "User",
                "assistant" => "Assistant",
                _ => "System",
            };
            prompt_parts.push(format!("{}: {}", label, msg.content));
        }
    }

    prompt_parts.push(String::new());
    prompt_parts.push(format!("User: {}", content));

    let mut full_prompt = prompt_parts.join("\n");

    // Prepend attachment context
    let attachment_ctx = build_attachment_prompt(&attachments);
    if !attachment_ctx.is_empty() {
        full_prompt = format!("{}\n\n{}", attachment_ctx, full_prompt);
    }

    // 6. Create TaskInput
    let input = TaskInput {
        prompt: full_prompt,
        system_prompt: String::new(),
        working_directory: working_dir,
        allowed_tools: None,
        max_budget_usd: None,
        timeout_seconds: 300,
        mcp_config_path: None,
        json_schema: None,
        attachments,
    };

    // 7. Execute and stream
    let pid = project_id.clone();
    let (_, mut rx) = backend.execute(input).await.map_err(|e| {
        let _ = app.emit(
            "chat-stream",
            serde_json::json!({"type": "error", "projectId": pid, "message": e}),
        );
        e
    })?;

    let message_id = Uuid::new_v4().to_string();
    let msg_id_clone = message_id.clone();
    let pid = project_id.clone();
    let bt = backend_type.clone();
    let app_clone = app.clone();
    let state_db = state.db.clone();

    tokio::spawn(async move {
        let mut full_output = String::new();
        let mut cost_usd: Option<f64> = None;

        while let Some(event) = rx.recv().await {
            match event {
                OutputEvent::Text(text) => {
                    full_output.push_str(&text);
                    let _ = app_clone.emit(
                        "chat-stream",
                        serde_json::json!({
                            "type": "chunk",
                            "projectId": pid,
                            "content": text,
                        }),
                    );
                }
                OutputEvent::Result(result) => {
                    full_output = result.output.clone();
                    cost_usd = result.cost_usd;
                }
                OutputEvent::Error(err) => {
                    let _ = app_clone.emit(
                        "chat-stream",
                        serde_json::json!({
                            "type": "error",
                            "projectId": pid,
                            "message": err,
                        }),
                    );
                    return;
                }
                _ => {}
            }
        }

        // Save assistant message to DB
        let now = chrono::Utc::now()
            .format("%Y-%m-%dT%H:%M:%S%.3fZ")
            .to_string();
        let assistant_msg = ProjectMessage {
            id: msg_id_clone.clone(),
            project_id: pid.clone(),
            role: "assistant".to_string(),
            content: full_output,
            backend: Some(bt.clone()),
            cost_usd,
            duration_ms: None,
            metadata: None,
            attachments: None,
            created_at: now,
        };

        if let Ok(db) = state_db.try_lock() {
            let _ = ProjectMessage::insert(&db.conn, &assistant_msg);
        }

        let _ = app_clone.emit(
            "chat-stream",
            serde_json::json!({
                "type": "done",
                "projectId": pid,
                "messageId": msg_id_clone,
                "backend": bt,
                "costUsd": cost_usd,
            }),
        );
    });

    Ok(message_id)
}

#[tauri::command]
pub async fn list_chat_messages(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<Vec<ProjectMessage>, String> {
    let db = state.db.lock().await;
    ProjectMessage::list_by_project(&db.conn, &project_id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn approve_chat_proposal(
    state: State<'_, AppState>,
    message_id: String,
    metadata: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    ProjectMessage::update_metadata(&db.conn, &message_id, &metadata).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn reject_chat_proposal(
    state: State<'_, AppState>,
    message_id: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    let metadata_json = r#"{"status":"rejected"}"#;
    ProjectMessage::update_metadata(&db.conn, &message_id, metadata_json)
        .map_err(|e| e.to_string())
}
