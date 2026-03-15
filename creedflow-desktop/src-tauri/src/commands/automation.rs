use crate::db::models::AutomationFlow;
use crate::state::AppState;
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub async fn list_automation_flows(
    state: State<'_, AppState>,
    project_id: Option<String>,
) -> Result<Vec<AutomationFlow>, String> {
    let db = state.db.lock().await;
    if let Some(pid) = project_id {
        AutomationFlow::all_for_project(&db.conn, &pid).map_err(|e| e.to_string())
    } else {
        AutomationFlow::all(&db.conn).map_err(|e| e.to_string())
    }
}

#[tauri::command]
pub async fn create_automation_flow(
    state: State<'_, AppState>,
    project_id: Option<String>,
    name: String,
    trigger_type: String,
    trigger_config: String,
    action_type: String,
    action_config: String,
    is_enabled: bool,
) -> Result<AutomationFlow, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let flow = AutomationFlow {
        id: Uuid::new_v4().to_string(),
        project_id,
        name,
        trigger_type,
        trigger_config,
        action_type,
        action_config,
        is_enabled,
        last_triggered_at: None,
        created_at: now.clone(),
        updated_at: now,
    };
    let db = state.db.lock().await;
    AutomationFlow::insert(&db.conn, &flow).map_err(|e| e.to_string())?;
    Ok(flow)
}

#[tauri::command]
pub async fn update_automation_flow(
    state: State<'_, AppState>,
    id: String,
    project_id: Option<String>,
    name: String,
    trigger_type: String,
    trigger_config: String,
    action_type: String,
    action_config: String,
    is_enabled: bool,
) -> Result<AutomationFlow, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let db = state.db.lock().await;

    // Get existing to preserve lastTriggeredAt and createdAt
    let existing = AutomationFlow::get(&db.conn, &id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "Automation flow not found".to_string())?;

    let flow = AutomationFlow {
        id,
        project_id,
        name,
        trigger_type,
        trigger_config,
        action_type,
        action_config,
        is_enabled,
        last_triggered_at: existing.last_triggered_at,
        created_at: existing.created_at,
        updated_at: now,
    };
    AutomationFlow::update(&db.conn, &flow).map_err(|e| e.to_string())?;
    Ok(flow)
}

#[tauri::command]
pub async fn delete_automation_flow(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    AutomationFlow::delete(&db.conn, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn toggle_automation_flow(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    let db = state.db.lock().await;
    AutomationFlow::toggle(&db.conn, &id).map_err(|e| e.to_string())
}
