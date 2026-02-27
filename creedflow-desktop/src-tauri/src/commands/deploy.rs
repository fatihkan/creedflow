use crate::state::AppState;
use rusqlite::params;
use serde::{Deserialize, Serialize};
use tauri::State;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeploymentInfo {
    pub id: String,
    pub project_id: String,
    pub environment: String,
    pub status: String,
    pub version: String,
    pub commit_hash: Option<String>,
    pub deployed_by: String,
    pub deploy_method: Option<String>,
    pub port: Option<i32>,
    pub container_id: Option<String>,
    pub process_id: Option<i32>,
    pub logs: Option<String>,
    pub fix_task_id: Option<String>,
    pub auto_fix_attempts: i32,
    pub created_at: String,
    pub completed_at: Option<String>,
}

impl DeploymentInfo {
    pub fn from_row(row: &rusqlite::Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            project_id: row.get("projectId")?,
            environment: row.get("environment")?,
            status: row.get("status")?,
            version: row.get("version")?,
            commit_hash: row.get("commitHash")?,
            deployed_by: row.get("deployedBy")?,
            deploy_method: row.get("deployMethod")?,
            port: row.get("port")?,
            container_id: row.get("containerId")?,
            process_id: row.get("processId")?,
            logs: row.get("logs")?,
            fix_task_id: row.get("fixTaskId")?,
            auto_fix_attempts: row.get("autoFixAttempts")?,
            created_at: row.get("createdAt")?,
            completed_at: row.get("completedAt")?,
        })
    }
}

#[tauri::command]
pub async fn list_deployments(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<Vec<DeploymentInfo>, String> {
    let db = state.db.lock().await;
    let mut stmt = db.conn.prepare(
        "SELECT * FROM deployment WHERE projectId = ?1 ORDER BY createdAt DESC"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map([&project_id], |row| DeploymentInfo::from_row(row))
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_deployment(
    state: State<'_, AppState>,
    project_id: String,
    environment: String,
    version: String,
    deploy_method: String,
) -> Result<DeploymentInfo, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let id = Uuid::new_v4().to_string();

    let db = state.db.lock().await;
    db.conn.execute(
        "INSERT INTO deployment (id, projectId, environment, status, version, deployedBy, deployMethod, createdAt)
         VALUES (?1, ?2, ?3, 'pending', ?4, 'user', ?5, ?6)",
        params![id, project_id, environment, version, deploy_method, now],
    ).map_err(|e| e.to_string())?;

    db.conn.query_row(
        "SELECT * FROM deployment WHERE id = ?1",
        [&id],
        |row| DeploymentInfo::from_row(row),
    ).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_deployment(
    state: State<'_, AppState>,
    id: String,
) -> Result<DeploymentInfo, String> {
    let db = state.db.lock().await;
    db.conn.query_row(
        "SELECT * FROM deployment WHERE id = ?1",
        [&id],
        |row| DeploymentInfo::from_row(row),
    ).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_deployments(
    state: State<'_, AppState>,
    ids: Vec<String>,
) -> Result<(), String> {
    let db = state.db.lock().await;
    for id in &ids {
        db.conn.execute(
            "DELETE FROM deployment WHERE id = ?1 AND status IN ('success', 'failed', 'rolled_back')",
            params![id],
        ).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn cancel_deployment(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute(
        "UPDATE deployment SET status = 'cancelled', completedAt = datetime('now') WHERE id = ?1 AND status IN ('pending', 'in_progress')",
        [&id],
    ).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn get_deployment_logs(
    state: State<'_, AppState>,
    id: String,
) -> Result<Option<String>, String> {
    let db = state.db.lock().await;
    let logs: Option<String> = db.conn.query_row(
        "SELECT logs FROM deployment WHERE id = ?1",
        [&id],
        |row| row.get(0),
    ).map_err(|e| e.to_string())?;
    Ok(logs)
}
