use crate::db::models::{AppNotification, HealthEvent};
use crate::state::AppState;
use tauri::State;

#[tauri::command]
pub async fn list_notifications(
    state: State<'_, AppState>,
    limit: Option<i32>,
) -> Result<Vec<AppNotification>, String> {
    let db = state.db.lock().await;
    AppNotification::recent(&db.conn, limit.unwrap_or(50))
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_unread_count(
    state: State<'_, AppState>,
) -> Result<i32, String> {
    let db = state.db.lock().await;
    AppNotification::unread_count(&db.conn)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn mark_notification_read(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    AppNotification::mark_read(&db.conn, &id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn mark_all_notifications_read(
    state: State<'_, AppState>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    AppNotification::mark_all_read(&db.conn)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn dismiss_notification(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    AppNotification::dismiss(&db.conn, &id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_notification(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    AppNotification::delete_one(&db.conn, &id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn clear_all_notifications(
    state: State<'_, AppState>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    AppNotification::clear_all(&db.conn)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_backend_health_status(
    state: State<'_, AppState>,
) -> Result<Vec<HealthEvent>, String> {
    let db = state.db.lock().await;
    HealthEvent::latest_by_target_type(&db.conn, "backend")
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_mcp_health_status(
    state: State<'_, AppState>,
) -> Result<Vec<HealthEvent>, String> {
    let db = state.db.lock().await;
    HealthEvent::latest_by_target_type(&db.conn, "mcp")
        .map_err(|e| e.to_string())
}
