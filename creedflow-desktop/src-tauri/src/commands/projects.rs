use crate::db::models::Project;
use crate::state::AppState;
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub async fn list_projects(state: State<'_, AppState>) -> Result<Vec<Project>, String> {
    let db = state.db.lock().await;
    Project::all(&db.conn).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_project(state: State<'_, AppState>, id: String) -> Result<Project, String> {
    let db = state.db.lock().await;
    Project::get(&db.conn, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_project(
    state: State<'_, AppState>,
    name: String,
    description: String,
    tech_stack: String,
    project_type: String,
) -> Result<Project, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let project = Project {
        id: Uuid::new_v4().to_string(),
        name,
        description,
        tech_stack,
        status: "planning".to_string(),
        directory_path: String::new(),
        project_type,
        telegram_chat_id: None,
        staging_pr_number: None,
        created_at: now.clone(),
        updated_at: now,
    };
    let db = state.db.lock().await;
    Project::insert(&db.conn, &project).map_err(|e| e.to_string())?;
    Ok(project)
}

#[tauri::command]
pub async fn update_project(
    state: State<'_, AppState>,
    project: Project,
) -> Result<Project, String> {
    let db = state.db.lock().await;
    Project::update(&db.conn, &project).map_err(|e| e.to_string())?;
    Ok(project)
}

#[tauri::command]
pub async fn delete_project(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    Project::delete(&db.conn, &id).map_err(|e| e.to_string())
}
