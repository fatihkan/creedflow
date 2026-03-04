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

// ─── Task Statistics ────────────────────────────────────────────────────────

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentTaskStats {
    pub agent_type: String,
    pub total: i64,
    pub passed: i64,
    pub failed: i64,
    pub needs_revision: i64,
    pub avg_duration_ms: Option<f64>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DailyCount {
    pub date: String,
    pub count: i64,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskStatistics {
    pub by_agent: Vec<AgentTaskStats>,
    pub daily_completed: Vec<DailyCount>,
    pub total_tasks: i64,
    pub success_rate: f64,
    pub avg_duration_ms: Option<f64>,
}

#[tauri::command]
pub async fn get_task_statistics(state: State<'_, AppState>) -> Result<TaskStatistics, String> {
    let db = state.db.lock().await;

    let total_tasks: i64 = db.conn
        .query_row("SELECT COUNT(*) FROM agentTask WHERE archivedAt IS NULL", [], |r| r.get(0))
        .map_err(|e| e.to_string())?;

    let passed_count: i64 = db.conn
        .query_row(
            "SELECT COUNT(*) FROM agentTask WHERE status = 'passed' AND archivedAt IS NULL",
            [],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;

    let completed: i64 = db.conn
        .query_row(
            "SELECT COUNT(*) FROM agentTask WHERE status IN ('passed', 'failed') AND archivedAt IS NULL",
            [],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;

    let success_rate = if completed > 0 {
        (passed_count as f64 / completed as f64) * 100.0
    } else {
        0.0
    };

    let avg_duration_ms: Option<f64> = db.conn
        .query_row(
            "SELECT AVG(durationMs) FROM agentTask WHERE durationMs IS NOT NULL AND archivedAt IS NULL",
            [],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;

    let mut by_agent_stmt = db.conn.prepare(
        "SELECT agentType,
                COUNT(*) as total,
                SUM(CASE WHEN status = 'passed' THEN 1 ELSE 0 END) as passed,
                SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
                SUM(CASE WHEN status = 'needs_revision' THEN 1 ELSE 0 END) as needs_revision,
                AVG(durationMs) as avg_duration
         FROM agentTask WHERE archivedAt IS NULL
         GROUP BY agentType ORDER BY total DESC"
    ).map_err(|e| e.to_string())?;

    let by_agent = by_agent_stmt.query_map([], |row| {
        Ok(AgentTaskStats {
            agent_type: row.get(0)?,
            total: row.get(1)?,
            passed: row.get(2)?,
            failed: row.get(3)?,
            needs_revision: row.get(4)?,
            avg_duration_ms: row.get(5)?,
        })
    }).map_err(|e| e.to_string())?
    .collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())?;

    let mut daily_stmt = db.conn.prepare(
        "SELECT DATE(completedAt) as day, COUNT(*) as cnt
         FROM agentTask
         WHERE completedAt IS NOT NULL
           AND completedAt >= datetime('now', '-30 days')
           AND archivedAt IS NULL
         GROUP BY day ORDER BY day"
    ).map_err(|e| e.to_string())?;

    let daily_completed = daily_stmt.query_map([], |row| {
        Ok(DailyCount {
            date: row.get(0)?,
            count: row.get(1)?,
        })
    }).map_err(|e| e.to_string())?
    .collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())?;

    Ok(TaskStatistics {
        by_agent,
        daily_completed,
        total_tasks,
        success_rate,
        avg_duration_ms,
    })
}
