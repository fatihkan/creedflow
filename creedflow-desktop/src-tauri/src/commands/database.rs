use serde::Serialize;
use tauri::State;
use crate::state::AppState;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DbInfo {
    pub path: String,
    pub size_bytes: u64,
    pub tables: Vec<TableInfo>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TableInfo {
    pub name: String,
    pub row_count: i64,
}

#[tauri::command]
pub async fn get_db_info(state: State<'_, AppState>) -> Result<DbInfo, String> {
    let db = state.db.lock().await;
    let path = db.conn.path()
        .unwrap_or("")
        .to_string();

    let size_bytes = std::fs::metadata(&path)
        .map(|m| m.len())
        .unwrap_or(0);

    let mut stmt = db.conn.prepare(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' ORDER BY name"
    ).map_err(|e| e.to_string())?;

    let tables: Vec<String> = stmt.query_map([], |row| {
        row.get::<_, String>(0)
    }).map_err(|e| e.to_string())?
    .filter_map(|r| r.ok())
    .collect();

    let mut table_infos = Vec::new();
    for table in tables {
        let count: i64 = db.conn
            .query_row(&format!("SELECT COUNT(*) FROM \"{}\"", table), [], |row| row.get(0))
            .unwrap_or(0);
        table_infos.push(TableInfo { name: table, row_count: count });
    }

    Ok(DbInfo {
        path,
        size_bytes,
        tables: table_infos,
    })
}

#[tauri::command]
pub async fn vacuum_database(state: State<'_, AppState>) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute_batch("VACUUM").map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn backup_database(state: State<'_, AppState>, dest_path: String) -> Result<(), String> {
    let db = state.db.lock().await;
    db.conn.execute("VACUUM INTO ?1", [&dest_path]).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn prune_old_logs(state: State<'_, AppState>, older_than_days: i64) -> Result<i64, String> {
    let db = state.db.lock().await;
    let count = db.conn.execute(
        "DELETE FROM agentLog WHERE createdAt < datetime('now', ?1)",
        [format!("-{} days", older_than_days)],
    ).map_err(|e| e.to_string())?;
    Ok(count as i64)
}
