use crate::db::models::Review;
use crate::state::AppState;
use rusqlite::params;
use tauri::State;

#[tauri::command]
pub async fn list_reviews(
    state: State<'_, AppState>,
    limit: Option<i64>,
    offset: Option<i64>,
) -> Result<Vec<Review>, String> {
    let db = state.db.lock().await;
    let lim = limit.unwrap_or(50);
    let off = offset.unwrap_or(0);
    let mut stmt = db.conn.prepare(
        "SELECT * FROM review ORDER BY createdAt DESC LIMIT ?1 OFFSET ?2"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map(params![lim, off], |row| Review::from_row(row))
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn approve_review(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    Review::approve(&db.conn, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn reject_review(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute(
        "UPDATE review SET isApproved = 0 WHERE id = ?1",
        params![id],
    ).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn list_reviews_for_task(
    state: State<'_, AppState>,
    task_id: String,
) -> Result<Vec<Review>, String> {
    let db = state.db.lock().await;
    let mut stmt = db.conn.prepare(
        "SELECT * FROM review WHERE taskId = ?1 ORDER BY createdAt DESC"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map([&task_id], |row| Review::from_row(row))
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_pending_review_count(state: State<'_, AppState>) -> Result<i32, String> {
    let db = state.db.lock().await;
    let count: i32 = db.conn.query_row(
        "SELECT COUNT(*) FROM review WHERE isApproved = 0",
        [],
        |row| row.get(0),
    ).map_err(|e| e.to_string())?;
    Ok(count)
}
