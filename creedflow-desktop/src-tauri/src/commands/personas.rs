use crate::db::models::AgentPersona;
use crate::state::AppState;
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub async fn get_agent_personas(state: State<'_, AppState>) -> Result<Vec<AgentPersona>, String> {
    let db = state.db.lock().await;
    AgentPersona::all(&db.conn).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_agent_persona(
    state: State<'_, AppState>,
    name: String,
    description: String,
    system_prompt: String,
    agent_types: Vec<String>,
    tags: Vec<String>,
) -> Result<AgentPersona, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let persona = AgentPersona {
        id: Uuid::new_v4().to_string(),
        name,
        description,
        system_prompt,
        agent_types,
        tags,
        is_built_in: false,
        is_enabled: true,
        created_at: now.clone(),
        updated_at: now,
    };
    let db = state.db.lock().await;
    AgentPersona::insert(&db.conn, &persona).map_err(|e| e.to_string())?;
    Ok(persona)
}

#[tauri::command]
pub async fn update_agent_persona(
    state: State<'_, AppState>,
    id: String,
    name: String,
    description: String,
    system_prompt: String,
    agent_types: Vec<String>,
    tags: Vec<String>,
    is_enabled: bool,
) -> Result<(), String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let persona = AgentPersona {
        id,
        name,
        description,
        system_prompt,
        agent_types,
        tags,
        is_built_in: false,
        is_enabled,
        created_at: String::new(),
        updated_at: now,
    };
    let db = state.db.lock().await;
    AgentPersona::update(&db.conn, &persona).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_agent_persona(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    AgentPersona::delete(&db.conn, &id).map_err(|e| e.to_string())
}
