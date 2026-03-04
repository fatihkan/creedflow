use crate::db::models::MCPServerConfig;
use crate::state::AppState;
use rusqlite::params;
use tauri::State;
use uuid::Uuid;

impl MCPServerConfig {
    pub fn from_row(row: &rusqlite::Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            name: row.get("name")?,
            command: row.get("command")?,
            arguments: row.get("arguments")?,
            environment_vars: row.get("environmentVars")?,
            is_enabled: row.get::<_, i32>("isEnabled")? != 0,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }

    pub fn all(conn: &rusqlite::Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM mcpServerConfig ORDER BY name")?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }
}

#[tauri::command]
pub async fn list_mcp_servers(state: State<'_, AppState>) -> Result<Vec<MCPServerConfig>, String> {
    let db = state.db.lock().await;
    MCPServerConfig::all(&db.conn).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_mcp_server(
    state: State<'_, AppState>,
    name: String,
    command: String,
    arguments: String,
    environment_vars: String,
) -> Result<MCPServerConfig, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let id = Uuid::new_v4().to_string();
    let db = state.db.lock().await;
    db.conn.execute(
        "INSERT INTO mcpServerConfig (id, name, command, arguments, environmentVars, isEnabled, createdAt, updatedAt)
         VALUES (?1, ?2, ?3, ?4, ?5, 1, ?6, ?7)",
        params![id, name, command, arguments, environment_vars, now, now],
    ).map_err(|e| e.to_string())?;
    db.conn.query_row(
        "SELECT * FROM mcpServerConfig WHERE id = ?1",
        [&id],
        |row| MCPServerConfig::from_row(row),
    ).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn update_mcp_server(
    state: State<'_, AppState>,
    id: String,
    name: String,
    command: String,
    arguments: String,
    environment_vars: String,
    is_enabled: bool,
) -> Result<MCPServerConfig, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let db = state.db.lock().await;
    db.conn.execute(
        "UPDATE mcpServerConfig SET name = ?1, command = ?2, arguments = ?3, environmentVars = ?4, isEnabled = ?5, updatedAt = ?6 WHERE id = ?7",
        params![name, command, arguments, environment_vars, is_enabled as i32, now, id],
    ).map_err(|e| e.to_string())?;
    db.conn.query_row(
        "SELECT * FROM mcpServerConfig WHERE id = ?1",
        [&id],
        |row| MCPServerConfig::from_row(row),
    ).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_mcp_server(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute("DELETE FROM mcpServerConfig WHERE id = ?1", [&id])
        .map_err(|e| e.to_string())?;
    Ok(())
}
