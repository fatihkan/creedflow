use crate::db::models::IssueTrackingConfig;
use crate::db::models::IssueMapping;
use crate::services::issue_tracking::LinearService;
use crate::state::AppState;
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub async fn list_issue_configs(
    state: State<'_, AppState>,
    project_id: Option<String>,
) -> Result<Vec<IssueTrackingConfig>, String> {
    let db = state.db.lock().await;
    if let Some(pid) = project_id {
        IssueTrackingConfig::all_for_project(&db.conn, &pid).map_err(|e| e.to_string())
    } else {
        IssueTrackingConfig::all(&db.conn).map_err(|e| e.to_string())
    }
}

#[tauri::command]
pub async fn create_issue_config(
    state: State<'_, AppState>,
    project_id: String,
    provider: String,
    name: String,
    credentials_json: String,
    config_json: String,
    sync_back_enabled: bool,
) -> Result<IssueTrackingConfig, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let config = IssueTrackingConfig {
        id: Uuid::new_v4().to_string(),
        project_id,
        provider,
        name,
        credentials_json,
        config_json,
        is_enabled: true,
        sync_back_enabled,
        last_sync_at: None,
        created_at: now.clone(),
        updated_at: now,
    };
    let db = state.db.lock().await;
    IssueTrackingConfig::insert(&db.conn, &config).map_err(|e| e.to_string())?;
    Ok(config)
}

#[tauri::command]
pub async fn update_issue_config(
    state: State<'_, AppState>,
    id: String,
    project_id: String,
    provider: String,
    name: String,
    credentials_json: String,
    config_json: String,
    is_enabled: bool,
    sync_back_enabled: bool,
) -> Result<(), String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let config = IssueTrackingConfig {
        id,
        project_id,
        provider,
        name,
        credentials_json,
        config_json,
        is_enabled,
        sync_back_enabled,
        last_sync_at: None,
        created_at: String::new(),
        updated_at: now,
    };
    let db = state.db.lock().await;
    IssueTrackingConfig::update(&db.conn, &config).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_issue_config(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    IssueTrackingConfig::delete(&db.conn, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn import_issues(
    state: State<'_, AppState>,
    config_id: String,
) -> Result<Vec<IssueMapping>, String> {
    let db = state.db.lock().await;
    let config = IssueTrackingConfig::get(&db.conn, &config_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "Config not found".to_string())?;

    match config.provider.as_str() {
        "linear" => {
            LinearService::import_issues(&db.conn, &config).map_err(|e| e.to_string())
        }
        "jira" => Err("Jira integration is not yet implemented".to_string()),
        _ => Err(format!("Unknown provider: {}", config.provider)),
    }
}

#[tauri::command]
pub async fn list_issue_mappings(
    state: State<'_, AppState>,
    config_id: String,
) -> Result<Vec<IssueMapping>, String> {
    let db = state.db.lock().await;
    IssueMapping::all_for_config(&db.conn, &config_id).map_err(|e| e.to_string())
}
