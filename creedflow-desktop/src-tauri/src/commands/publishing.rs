use crate::db::models::{Publication, PublishingChannel};
use crate::state::AppState;
use rusqlite::params;
use tauri::State;
use uuid::Uuid;

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

#[tauri::command]
pub async fn create_channel(
    state: State<'_, AppState>,
    name: String,
    channel_type: String,
    credentials_json: String,
    default_tags: String,
) -> Result<PublishingChannel, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let id = Uuid::new_v4().to_string();
    let db = state.db.lock().await;
    db.conn.execute(
        "INSERT INTO publishingChannel (id, name, channelType, credentialsJSON, isEnabled, defaultTags, createdAt, updatedAt)
         VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6, ?7)",
        params![id, name, channel_type, credentials_json, default_tags, now, now],
    ).map_err(|e| e.to_string())?;
    db.conn.query_row(
        "SELECT * FROM publishingChannel WHERE id = ?1",
        [&id],
        |row| PublishingChannel::from_row(row),
    ).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn update_channel(
    state: State<'_, AppState>,
    id: String,
    name: String,
    channel_type: String,
    credentials_json: String,
    default_tags: String,
    is_enabled: bool,
) -> Result<PublishingChannel, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let db = state.db.lock().await;
    db.conn.execute(
        "UPDATE publishingChannel SET name = ?1, channelType = ?2, credentialsJSON = ?3, defaultTags = ?4, isEnabled = ?5, updatedAt = ?6 WHERE id = ?7",
        params![name, channel_type, credentials_json, default_tags, is_enabled as i32, now, id],
    ).map_err(|e| e.to_string())?;
    db.conn.query_row(
        "SELECT * FROM publishingChannel WHERE id = ?1",
        [&id],
        |row| PublishingChannel::from_row(row),
    ).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_channel(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute("DELETE FROM publishingChannel WHERE id = ?1", [&id])
        .map_err(|e| e.to_string())?;
    Ok(())
}
