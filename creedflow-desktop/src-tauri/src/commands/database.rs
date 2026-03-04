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

#[tauri::command]
pub async fn export_database_json(state: State<'_, AppState>, dest_path: String) -> Result<(), String> {
    let db = state.db.lock().await;

    let mut stmt = db.conn.prepare(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' ORDER BY name"
    ).map_err(|e| e.to_string())?;

    let tables: Vec<String> = stmt.query_map([], |row| {
        row.get::<_, String>(0)
    }).map_err(|e| e.to_string())?
    .filter_map(|r| r.ok())
    .collect();

    let mut export = serde_json::Map::new();

    for table in &tables {
        let mut tbl_stmt = db.conn.prepare(&format!("SELECT * FROM \"{}\"", table))
            .map_err(|e| e.to_string())?;
        let col_count = tbl_stmt.column_count();
        let col_names: Vec<String> = (0..col_count)
            .map(|i| tbl_stmt.column_name(i).unwrap_or("").to_string())
            .collect();

        let rows: Vec<serde_json::Value> = tbl_stmt
            .query_map([], |row| {
                let mut obj = serde_json::Map::new();
                for (i, name) in col_names.iter().enumerate() {
                    let val: rusqlite::Result<String> = row.get(i);
                    obj.insert(
                        name.clone(),
                        match val {
                            Ok(s) => serde_json::Value::String(s),
                            Err(_) => {
                                let int_val: rusqlite::Result<i64> = row.get(i);
                                match int_val {
                                    Ok(n) => serde_json::Value::Number(n.into()),
                                    Err(_) => {
                                        let float_val: rusqlite::Result<f64> = row.get(i);
                                        match float_val {
                                            Ok(f) => serde_json::Number::from_f64(f)
                                                .map(serde_json::Value::Number)
                                                .unwrap_or(serde_json::Value::Null),
                                            Err(_) => serde_json::Value::Null,
                                        }
                                    }
                                }
                            }
                        },
                    );
                }
                Ok(serde_json::Value::Object(obj))
            })
            .map_err(|e| e.to_string())?
            .filter_map(|r| r.ok())
            .collect();

        export.insert(table.clone(), serde_json::Value::Array(rows));
    }

    let json = serde_json::to_string_pretty(&serde_json::Value::Object(export))
        .map_err(|e| format!("Failed to serialize: {}", e))?;
    std::fs::write(&dest_path, json)
        .map_err(|e| format!("Failed to write file: {}", e))?;
    Ok(())
}

#[tauri::command]
pub async fn factory_reset_database(state: State<'_, AppState>) -> Result<(), String> {
    let db = state.db.lock().await;

    // Delete in dependency order to avoid FK constraint issues
    let tables_in_order = [
        "promptUsage",
        "promptChainStep",
        "promptChain",
        "promptVersion",
        "promptTag",
        "prompt",
        "taskDependency",
        "taskComment",
        "publication",
        "publishingChannel",
        "generatedAsset",
        "review",
        "agentLog",
        "costTracking",
        "deployment",
        "archivedTask",
        "agentTask",
        "feature",
        "projectChatMessage",
        "project",
        "appNotification",
        "healthEvent",
        "mcpServerConfig",
    ];

    for table in &tables_in_order {
        // Try each table, skip if it doesn't exist
        let _ = db.conn.execute(&format!("DELETE FROM \"{}\"", table), []);
    }

    log::info!("Factory reset: all user data cleared");
    Ok(())
}
