use crate::db::models::ProjectMessage;
use crate::state::AppState;
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub async fn send_chat_message(
    state: State<'_, AppState>,
    project_id: String,
    content: String,
    role: String,
) -> Result<ProjectMessage, String> {
    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();
    let msg = ProjectMessage {
        id: Uuid::new_v4().to_string(),
        project_id,
        role,
        content,
        backend: None,
        cost_usd: None,
        duration_ms: None,
        metadata: None,
        created_at: now,
    };
    let db = state.db.lock().await;
    ProjectMessage::insert(&db.conn, &msg).map_err(|e| e.to_string())?;
    Ok(msg)
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
    ProjectMessage::update_metadata(&db.conn, &message_id, &metadata)
        .map_err(|e| e.to_string())
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
