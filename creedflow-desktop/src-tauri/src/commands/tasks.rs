use crate::db::models::{AgentTask, TaskDependency};
use crate::state::AppState;
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub async fn list_tasks(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<Vec<AgentTask>, String> {
    let db = state.db.lock().await;
    AgentTask::all_for_project(&db.conn, &project_id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_task(state: State<'_, AppState>, id: String) -> Result<AgentTask, String> {
    let db = state.db.lock().await;
    AgentTask::get(&db.conn, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_task(
    state: State<'_, AppState>,
    project_id: String,
    title: String,
    description: String,
    agent_type: String,
    priority: Option<i32>,
) -> Result<AgentTask, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let task = AgentTask {
        id: Uuid::new_v4().to_string(),
        project_id,
        feature_id: None,
        agent_type,
        title,
        description,
        priority: priority.unwrap_or(0),
        status: "queued".to_string(),
        result: None,
        error_message: None,
        retry_count: 0,
        max_retries: 3,
        session_id: None,
        branch_name: None,
        pr_number: None,
        cost_usd: None,
        duration_ms: None,
        created_at: now.clone(),
        updated_at: now,
        started_at: None,
        completed_at: None,
        backend: None,
        prompt_chain_id: None,
    };
    let db = state.db.lock().await;
    AgentTask::insert(&db.conn, &task).map_err(|e| e.to_string())?;
    Ok(task)
}

#[tauri::command]
pub async fn update_task_status(
    state: State<'_, AppState>,
    id: String,
    status: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    AgentTask::update_status(&db.conn, &id, &status).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_task_dependencies(
    state: State<'_, AppState>,
    task_id: String,
) -> Result<Vec<TaskDependency>, String> {
    let db = state.db.lock().await;
    TaskDependency::for_task(&db.conn, &task_id).map_err(|e| e.to_string())
}
