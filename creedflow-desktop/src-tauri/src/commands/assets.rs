use crate::db::models::GeneratedAsset;
use crate::state::AppState;
use tauri::State;

#[tauri::command]
pub async fn list_assets(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<Vec<GeneratedAsset>, String> {
    let db = state.db.lock().await;
    GeneratedAsset::for_project(&db.conn, &project_id).map_err(|e| e.to_string())
}
