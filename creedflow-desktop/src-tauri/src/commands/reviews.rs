use crate::db::models::Review;
use crate::state::AppState;
use tauri::State;

#[tauri::command]
pub async fn list_reviews(state: State<'_, AppState>) -> Result<Vec<Review>, String> {
    let db = state.db.lock().await;
    Review::all(&db.conn).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn approve_review(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    Review::approve(&db.conn, &id).map_err(|e| e.to_string())
}
