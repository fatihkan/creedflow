use crate::db::models::{CostSummary, CostTracking};
use crate::state::AppState;
use tauri::State;

#[tauri::command]
pub async fn get_cost_summary(state: State<'_, AppState>) -> Result<CostSummary, String> {
    let db = state.db.lock().await;
    CostTracking::summary(&db.conn).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_costs_by_project(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<Vec<CostTracking>, String> {
    let db = state.db.lock().await;
    CostTracking::by_project(&db.conn, &project_id).map_err(|e| e.to_string())
}
