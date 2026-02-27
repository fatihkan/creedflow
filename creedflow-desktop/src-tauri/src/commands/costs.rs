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

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CostBreakdown {
    pub label: String,
    pub cost: f64,
    pub tasks: i64,
    pub tokens: i64,
}

#[tauri::command]
pub async fn get_cost_by_agent(state: State<'_, AppState>) -> Result<Vec<CostBreakdown>, String> {
    let db = state.db.lock().await;
    let mut stmt = db.conn.prepare(
        "SELECT agentType, SUM(costUsd) as cost, COUNT(*) as tasks, SUM(inputTokens + outputTokens) as tokens
         FROM costTracking GROUP BY agentType ORDER BY cost DESC"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map([], |row| {
        Ok(CostBreakdown {
            label: row.get::<_, String>(0)?,
            cost: row.get(1)?,
            tasks: row.get(2)?,
            tokens: row.get(3)?,
        })
    }).map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_cost_by_backend(state: State<'_, AppState>) -> Result<Vec<CostBreakdown>, String> {
    let db = state.db.lock().await;
    let mut stmt = db.conn.prepare(
        "SELECT COALESCE(backend, 'unknown') as backend, SUM(costUsd) as cost, COUNT(*) as tasks, SUM(inputTokens + outputTokens) as tokens
         FROM costTracking GROUP BY backend ORDER BY cost DESC"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map([], |row| {
        Ok(CostBreakdown {
            label: row.get::<_, String>(0)?,
            cost: row.get(1)?,
            tasks: row.get(2)?,
            tokens: row.get(3)?,
        })
    }).map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_cost_timeline(state: State<'_, AppState>) -> Result<Vec<CostBreakdown>, String> {
    let db = state.db.lock().await;
    let mut stmt = db.conn.prepare(
        "SELECT DATE(createdAt) as day, SUM(costUsd) as cost, COUNT(*) as tasks, SUM(inputTokens + outputTokens) as tokens
         FROM costTracking WHERE createdAt >= datetime('now', '-30 days')
         GROUP BY day ORDER BY day"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map([], |row| {
        Ok(CostBreakdown {
            label: row.get::<_, String>(0)?,
            cost: row.get(1)?,
            tasks: row.get(2)?,
            tokens: row.get(3)?,
        })
    }).map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}
