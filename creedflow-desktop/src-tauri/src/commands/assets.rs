use crate::db::models::GeneratedAsset;
use crate::services::asset_versioning::AssetVersioningService;
use crate::state::AppState;
use rusqlite::params;
use tauri::State;

#[tauri::command]
pub async fn list_assets(
    state: State<'_, AppState>,
    project_id: String,
    limit: Option<i64>,
    offset: Option<i64>,
) -> Result<Vec<GeneratedAsset>, String> {
    let db = state.db.lock().await;
    let lim = limit.unwrap_or(50);
    let off = offset.unwrap_or(0);
    let mut stmt = db.conn.prepare(
        "SELECT * FROM generatedAsset WHERE projectId = ?1 ORDER BY createdAt DESC LIMIT ?2 OFFSET ?3"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map(params![project_id, lim, off], |row| GeneratedAsset::from_row(row))
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_asset(
    state: State<'_, AppState>,
    id: String,
) -> Result<GeneratedAsset, String> {
    let db = state.db.lock().await;
    db.conn
        .query_row(
            "SELECT * FROM generatedAsset WHERE id = ?1",
            [&id],
            |row| GeneratedAsset::from_row(row),
        )
        .map_err(|e| format!("Asset not found: {}", e))
}

#[tauri::command]
pub async fn get_asset_versions(
    state: State<'_, AppState>,
    asset_id: String,
) -> Result<Vec<GeneratedAsset>, String> {
    AssetVersioningService::get_version_chain(&state.db, &asset_id).await
}

#[tauri::command]
pub async fn approve_asset(
    state: State<'_, AppState>,
    id: String,
    approved: bool,
) -> Result<(), String> {
    let status = if approved { "approved" } else { "rejected" };
    let db = state.db.lock().await;
    db.conn
        .execute(
            "UPDATE generatedAsset SET status = ?1, updatedAt = datetime('now') WHERE id = ?2",
            params![status, id],
        )
        .map_err(|e| format!("Failed to update asset: {}", e))?;
    Ok(())
}

#[tauri::command]
pub async fn delete_asset(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    // Get file path before deleting record
    let file_path: Option<String> = db
        .conn
        .query_row(
            "SELECT filePath FROM generatedAsset WHERE id = ?1",
            [&id],
            |row| row.get(0),
        )
        .ok();

    db.conn
        .execute("DELETE FROM generatedAsset WHERE id = ?1", [&id])
        .map_err(|e| format!("Failed to delete asset: {}", e))?;

    // Best-effort file removal
    if let Some(path) = file_path {
        let _ = std::fs::remove_file(&path);
    }

    Ok(())
}
