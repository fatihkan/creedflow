use creedflow_desktop_lib::db::Database;
use serde_json::{json, Value};

/// Return the list of all MCP resources.
pub fn list_resources() -> Vec<Value> {
    vec![
        json!({
            "uri": "creedflow://projects",
            "name": "All Projects",
            "description": "List of all CreedFlow projects",
            "mimeType": "application/json"
        }),
        json!({
            "uri": "creedflow://tasks/queue",
            "name": "Task Queue",
            "description": "Current task queue with status",
            "mimeType": "application/json"
        }),
        json!({
            "uri": "creedflow://costs/summary",
            "name": "Cost Summary",
            "description": "Cost tracking summary across all projects",
            "mimeType": "application/json"
        }),
        json!({
            "uri": "creedflow://projects/{id}/assets",
            "name": "Project Assets",
            "description": "Generated assets for a specific project",
            "mimeType": "application/json"
        }),
        json!({
            "uri": "creedflow://publications",
            "name": "Publications",
            "description": "All published content",
            "mimeType": "application/json"
        }),
    ]
}

/// Read a resource by URI and return JSON content.
pub fn read_resource(db: &Database, uri: &str) -> Result<String, String> {
    if uri == "creedflow://projects" {
        read_projects(db)
    } else if uri == "creedflow://tasks/queue" {
        read_task_queue(db)
    } else if uri == "creedflow://costs/summary" {
        read_cost_summary(db)
    } else if uri.starts_with("creedflow://projects/") && uri.ends_with("/assets") {
        let id = uri
            .strip_prefix("creedflow://projects/")
            .and_then(|s| s.strip_suffix("/assets"))
            .ok_or_else(|| "Invalid asset URI".to_string())?;
        read_project_assets(db, id)
    } else if uri == "creedflow://publications" {
        read_publications(db)
    } else {
        Err(format!("Unknown resource URI: {}", uri))
    }
}

fn read_projects(db: &Database) -> Result<String, String> {
    let mut stmt = db.conn.prepare(
        "SELECT id, name, description, techStack, status, projectType, createdAt, updatedAt FROM project ORDER BY updatedAt DESC"
    ).map_err(|e| e.to_string())?;

    let projects: Vec<Value> = stmt.query_map([], |row| {
        Ok(json!({
            "id": row.get::<_, String>(0)?,
            "name": row.get::<_, String>(1)?,
            "description": row.get::<_, String>(2)?,
            "techStack": row.get::<_, String>(3)?,
            "status": row.get::<_, String>(4)?,
            "projectType": row.get::<_, String>(5)?,
            "createdAt": row.get::<_, String>(6)?,
            "updatedAt": row.get::<_, String>(7)?
        }))
    }).map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();

    Ok(json!({"projects": projects}).to_string())
}

fn read_task_queue(db: &Database) -> Result<String, String> {
    let mut stmt = db.conn.prepare(
        "SELECT t.id, t.projectId, t.agentType, t.title, t.status, t.priority, t.retryCount, t.backend, p.name as projectName
         FROM agentTask t
         LEFT JOIN project p ON p.id = t.projectId
         WHERE t.status IN ('queued', 'in_progress')
         ORDER BY t.priority DESC, t.createdAt"
    ).map_err(|e| e.to_string())?;

    let tasks: Vec<Value> = stmt.query_map([], |row| {
        Ok(json!({
            "id": row.get::<_, String>(0)?,
            "projectId": row.get::<_, String>(1)?,
            "agentType": row.get::<_, String>(2)?,
            "title": row.get::<_, String>(3)?,
            "status": row.get::<_, String>(4)?,
            "priority": row.get::<_, i32>(5)?,
            "retryCount": row.get::<_, i32>(6)?,
            "backend": row.get::<_, Option<String>>(7)?,
            "projectName": row.get::<_, Option<String>>(8)?
        }))
    }).map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();

    Ok(json!({"queue": tasks, "count": tasks.len()}).to_string())
}

fn read_cost_summary(db: &Database) -> Result<String, String> {
    use creedflow_desktop_lib::db::models::CostTracking;
    let summary = CostTracking::summary(&db.conn).map_err(|e| e.to_string())?;
    Ok(serde_json::to_string(&summary).unwrap())
}

fn read_project_assets(db: &Database, project_id: &str) -> Result<String, String> {
    use creedflow_desktop_lib::db::models::GeneratedAsset;
    let assets = GeneratedAsset::for_project(&db.conn, project_id)
        .map_err(|e| e.to_string())?;
    Ok(serde_json::to_string(&assets).unwrap())
}

fn read_publications(db: &Database) -> Result<String, String> {
    let mut stmt = db.conn.prepare(
        "SELECT pub.id, pub.assetId, pub.projectId, pub.channelId, pub.status, pub.publishedUrl, pub.createdAt,
                ch.name as channelName, ch.channelType, p.name as projectName
         FROM publication pub
         LEFT JOIN publishingChannel ch ON ch.id = pub.channelId
         LEFT JOIN project p ON p.id = pub.projectId
         ORDER BY pub.createdAt DESC
         LIMIT 100"
    ).map_err(|e| e.to_string())?;

    let pubs: Vec<Value> = stmt.query_map([], |row| {
        Ok(json!({
            "id": row.get::<_, String>(0)?,
            "assetId": row.get::<_, String>(1)?,
            "projectId": row.get::<_, String>(2)?,
            "channelId": row.get::<_, String>(3)?,
            "status": row.get::<_, String>(4)?,
            "publishedUrl": row.get::<_, Option<String>>(5)?,
            "createdAt": row.get::<_, String>(6)?,
            "channelName": row.get::<_, Option<String>>(7)?,
            "channelType": row.get::<_, Option<String>>(8)?,
            "projectName": row.get::<_, Option<String>>(9)?
        }))
    }).map_err(|e| e.to_string())?
        .filter_map(|r| r.ok())
        .collect();

    Ok(json!({"publications": pubs}).to_string())
}
