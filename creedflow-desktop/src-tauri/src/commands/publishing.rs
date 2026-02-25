use crate::db::models::{Publication, PublishingChannel};
use crate::state::AppState;
use tauri::State;

#[tauri::command]
pub async fn list_channels(state: State<'_, AppState>) -> Result<Vec<PublishingChannel>, String> {
    let db = state.db.lock().await;
    PublishingChannel::all(&db.conn).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn list_publications(state: State<'_, AppState>) -> Result<Vec<Publication>, String> {
    let db = state.db.lock().await;
    Publication::all(&db.conn).map_err(|e| e.to_string())
}
