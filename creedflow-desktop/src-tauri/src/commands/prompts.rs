use crate::db::models::Prompt;
use crate::state::AppState;
use rusqlite::params;
use tauri::State;
use uuid::Uuid;

impl Prompt {
    pub fn all(conn: &rusqlite::Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM prompt ORDER BY updatedAt DESC")?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn from_row(row: &rusqlite::Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            title: row.get("title")?,
            content: row.get("content")?,
            source: row.get("source")?,
            category: row.get("category")?,
            contributor: row.get("contributor")?,
            is_built_in: row.get::<_, i32>("isBuiltIn")? != 0,
            is_favorite: row.get::<_, i32>("isFavorite")? != 0,
            version: row.get("version")?,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }
}

#[tauri::command]
pub async fn list_prompts(state: State<'_, AppState>) -> Result<Vec<Prompt>, String> {
    let db = state.db.lock().await;
    Prompt::all(&db.conn).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_prompt(
    state: State<'_, AppState>,
    title: String,
    content: String,
    category: String,
) -> Result<Prompt, String> {
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let id = Uuid::new_v4().to_string();

    let db = state.db.lock().await;
    db.conn.execute(
        "INSERT INTO prompt (id, title, content, source, category, createdAt, updatedAt)
         VALUES (?1, ?2, ?3, 'user', ?4, ?5, ?6)",
        params![id, title, content, category, now, now],
    ).map_err(|e| e.to_string())?;

    db.conn.query_row(
        "SELECT * FROM prompt WHERE id = ?1",
        [&id],
        |row| Prompt::from_row(row),
    ).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_prompt(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute("DELETE FROM prompt WHERE id = ?1", [&id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn toggle_favorite(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute(
        "UPDATE prompt SET isFavorite = CASE WHEN isFavorite = 0 THEN 1 ELSE 0 END WHERE id = ?1",
        [&id],
    ).map_err(|e| e.to_string())?;
    Ok(())
}
