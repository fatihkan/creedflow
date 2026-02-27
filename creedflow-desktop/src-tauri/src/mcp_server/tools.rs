use creedflow_desktop_lib::db::Database;
use creedflow_desktop_lib::db::models::*;
use rusqlite::params;
use serde_json::{json, Value};

/// Return the list of all MCP tools with their schemas.
pub fn list_tools() -> Vec<Value> {
    vec![
        tool_def("create-project", "Create a new project", json!({
            "type": "object",
            "properties": {
                "name": { "type": "string", "description": "Project name" },
                "description": { "type": "string", "description": "Project description" },
                "techStack": { "type": "string", "description": "Technology stack" },
                "projectType": { "type": "string", "description": "Project type (software, content, image, video, general)" }
            },
            "required": ["name", "description"]
        })),
        tool_def("create-task", "Create a task for a project", json!({
            "type": "object",
            "properties": {
                "projectId": { "type": "string" },
                "title": { "type": "string" },
                "description": { "type": "string" },
                "agentType": { "type": "string" },
                "priority": { "type": "number" }
            },
            "required": ["projectId", "title", "description", "agentType"]
        })),
        tool_def("update-task-status", "Update task status", json!({
            "type": "object",
            "properties": {
                "id": { "type": "string" },
                "status": { "type": "string", "description": "queued, in_progress, passed, failed, needs_revision, cancelled" }
            },
            "required": ["id", "status"]
        })),
        tool_def("get-project-tasks", "List tasks for a project", json!({
            "type": "object",
            "properties": {
                "projectId": { "type": "string" }
            },
            "required": ["projectId"]
        })),
        tool_def("run-analyzer", "Trigger analyzer agent for a project", json!({
            "type": "object",
            "properties": {
                "projectId": { "type": "string" }
            },
            "required": ["projectId"]
        })),
        tool_def("get-cost-summary", "Get cost tracking summary", json!({
            "type": "object",
            "properties": {}
        })),
        tool_def("search-prompts", "Search prompt library", json!({
            "type": "object",
            "properties": {
                "query": { "type": "string" },
                "category": { "type": "string" }
            }
        })),
        tool_def("list-assets", "List generated assets for a project", json!({
            "type": "object",
            "properties": {
                "projectId": { "type": "string" }
            },
            "required": ["projectId"]
        })),
        tool_def("get-asset", "Get asset details by ID", json!({
            "type": "object",
            "properties": {
                "id": { "type": "string" }
            },
            "required": ["id"]
        })),
        tool_def("list-asset-versions", "Get version chain for an asset", json!({
            "type": "object",
            "properties": {
                "assetId": { "type": "string" }
            },
            "required": ["assetId"]
        })),
        tool_def("approve-asset", "Approve or reject an asset", json!({
            "type": "object",
            "properties": {
                "id": { "type": "string" },
                "approved": { "type": "boolean" }
            },
            "required": ["id", "approved"]
        })),
        tool_def("list-publications", "List all publications", json!({
            "type": "object",
            "properties": {}
        })),
        tool_def("list-publishing-channels", "List configured publishing channels", json!({
            "type": "object",
            "properties": {}
        })),
    ]
}

fn tool_def(name: &str, description: &str, input_schema: Value) -> Value {
    json!({
        "name": name,
        "description": description,
        "inputSchema": input_schema
    })
}

/// Execute a tool call and return the result as a JSON string.
pub fn call_tool(db: &Database, name: &str, args: &Value) -> Result<String, String> {
    match name {
        "create-project" => {
            let name = str_arg(args, "name")?;
            let desc = str_arg(args, "description")?;
            let tech = args.get("techStack").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let ptype = args.get("projectType").and_then(|v| v.as_str()).unwrap_or("software").to_string();
            let id = uuid::Uuid::new_v4().to_string();
            let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
            let dir = dirs::home_dir().unwrap_or_default()
                .join("CreedFlow").join("projects").join(&name);

            db.conn.execute(
                "INSERT INTO project (id, name, description, techStack, status, directoryPath, projectType, createdAt, updatedAt)
                 VALUES (?1, ?2, ?3, ?4, 'planning', ?5, ?6, ?7, ?8)",
                params![id, name, desc, tech, dir.to_string_lossy().to_string(), ptype, now, now],
            ).map_err(|e| e.to_string())?;

            Ok(json!({"id": id, "name": name, "status": "planning"}).to_string())
        }

        "create-task" => {
            let project_id = str_arg(args, "projectId")?;
            let title = str_arg(args, "title")?;
            let desc = str_arg(args, "description")?;
            let agent_type = str_arg(args, "agentType")?;
            let priority = args.get("priority").and_then(|v| v.as_i64()).unwrap_or(5);
            let id = uuid::Uuid::new_v4().to_string();
            let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();

            db.conn.execute(
                "INSERT INTO agentTask (id, projectId, agentType, title, description, priority, status, retryCount, maxRetries, createdAt, updatedAt)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'queued', 0, 3, ?7, ?8)",
                params![id, project_id, agent_type, title, desc, priority, now, now],
            ).map_err(|e| e.to_string())?;

            Ok(json!({"id": id, "status": "queued"}).to_string())
        }

        "update-task-status" => {
            let id = str_arg(args, "id")?;
            let status = str_arg(args, "status")?;
            db.conn.execute(
                "UPDATE agentTask SET status = ?1, updatedAt = datetime('now') WHERE id = ?2",
                params![status, id],
            ).map_err(|e| e.to_string())?;
            Ok(json!({"id": id, "status": status}).to_string())
        }

        "get-project-tasks" => {
            let project_id = str_arg(args, "projectId")?;
            let mut stmt = db.conn.prepare(
                "SELECT id, title, agentType, status, priority FROM agentTask WHERE projectId = ?1 ORDER BY priority DESC, createdAt"
            ).map_err(|e| e.to_string())?;
            let tasks: Vec<Value> = stmt.query_map([&project_id], |row| {
                Ok(json!({
                    "id": row.get::<_, String>(0)?,
                    "title": row.get::<_, String>(1)?,
                    "agentType": row.get::<_, String>(2)?,
                    "status": row.get::<_, String>(3)?,
                    "priority": row.get::<_, i32>(4)?
                }))
            }).map_err(|e| e.to_string())?
                .filter_map(|r| r.ok())
                .collect();
            Ok(json!({"tasks": tasks}).to_string())
        }

        "run-analyzer" => {
            let project_id = str_arg(args, "projectId")?;
            let id = uuid::Uuid::new_v4().to_string();
            let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
            db.conn.execute(
                "INSERT INTO agentTask (id, projectId, agentType, title, description, priority, status, retryCount, maxRetries, createdAt, updatedAt)
                 VALUES (?1, ?2, 'analyzer', 'Deep Analysis', 'Analyze project architecture and create task breakdown', 10, 'queued', 0, 3, ?3, ?4)",
                params![id, project_id, now, now],
            ).map_err(|e| e.to_string())?;
            Ok(json!({"taskId": id, "message": "Analyzer task queued"}).to_string())
        }

        "get-cost-summary" => {
            let summary = CostTracking::summary(&db.conn).map_err(|e| e.to_string())?;
            Ok(serde_json::to_string(&summary).unwrap())
        }

        "search-prompts" => {
            let query = args.get("query").and_then(|v| v.as_str()).unwrap_or("");
            let category = args.get("category").and_then(|v| v.as_str());
            let sql = if let Some(cat) = category {
                format!(
                    "SELECT id, title, category, content FROM prompt WHERE category = '{}' AND (title LIKE '%{}%' OR content LIKE '%{}%') ORDER BY updatedAt DESC LIMIT 20",
                    cat, query, query
                )
            } else {
                format!(
                    "SELECT id, title, category, content FROM prompt WHERE title LIKE '%{}%' OR content LIKE '%{}%' ORDER BY updatedAt DESC LIMIT 20",
                    query, query
                )
            };
            let mut stmt = db.conn.prepare(&sql).map_err(|e| e.to_string())?;
            let prompts: Vec<Value> = stmt.query_map([], |row| {
                Ok(json!({
                    "id": row.get::<_, String>(0)?,
                    "title": row.get::<_, String>(1)?,
                    "category": row.get::<_, String>(2)?,
                    "content": row.get::<_, String>(3)?
                }))
            }).map_err(|e| e.to_string())?
                .filter_map(|r| r.ok())
                .collect();
            Ok(json!({"prompts": prompts}).to_string())
        }

        "list-assets" => {
            let project_id = str_arg(args, "projectId")?;
            let assets = GeneratedAsset::for_project(&db.conn, &project_id)
                .map_err(|e| e.to_string())?;
            Ok(serde_json::to_string(&assets).unwrap())
        }

        "get-asset" => {
            let id = str_arg(args, "id")?;
            let asset: GeneratedAsset = db.conn.query_row(
                "SELECT * FROM generatedAsset WHERE id = ?1",
                [&id],
                |row| GeneratedAsset::from_row(row),
            ).map_err(|e| format!("Asset not found: {}", e))?;
            Ok(serde_json::to_string(&asset).unwrap())
        }

        "list-asset-versions" => {
            let asset_id = str_arg(args, "assetId")?;
            // Simple chain walk
            let mut chain = Vec::new();
            let mut current = Some(asset_id.clone());
            while let Some(id) = &current {
                let asset: Option<GeneratedAsset> = db.conn.query_row(
                    "SELECT * FROM generatedAsset WHERE id = ?1",
                    [id],
                    |row| GeneratedAsset::from_row(row),
                ).ok();
                match asset {
                    Some(a) => {
                        let next: Option<String> = db.conn.query_row(
                            "SELECT id FROM generatedAsset WHERE parentAssetId = ?1",
                            [&a.id],
                            |row| row.get(0),
                        ).ok();
                        chain.push(a);
                        current = next;
                    }
                    None => break,
                }
            }
            Ok(serde_json::to_string(&chain).unwrap())
        }

        "approve-asset" => {
            let id = str_arg(args, "id")?;
            let approved = args.get("approved").and_then(|v| v.as_bool()).unwrap_or(true);
            let status = if approved { "approved" } else { "rejected" };
            db.conn.execute(
                "UPDATE generatedAsset SET status = ?1, updatedAt = datetime('now') WHERE id = ?2",
                params![status, id],
            ).map_err(|e| e.to_string())?;
            Ok(json!({"id": id, "status": status}).to_string())
        }

        "list-publications" => {
            let mut stmt = db.conn.prepare(
                "SELECT id, assetId, projectId, channelId, status, publishedUrl, createdAt FROM publication ORDER BY createdAt DESC LIMIT 50"
            ).map_err(|e| e.to_string())?;
            let pubs: Vec<Value> = stmt.query_map([], |row| {
                Ok(json!({
                    "id": row.get::<_, String>(0)?,
                    "assetId": row.get::<_, String>(1)?,
                    "projectId": row.get::<_, String>(2)?,
                    "channelId": row.get::<_, String>(3)?,
                    "status": row.get::<_, String>(4)?,
                    "publishedUrl": row.get::<_, Option<String>>(5)?,
                    "createdAt": row.get::<_, String>(6)?
                }))
            }).map_err(|e| e.to_string())?
                .filter_map(|r| r.ok())
                .collect();
            Ok(json!({"publications": pubs}).to_string())
        }

        "list-publishing-channels" => {
            let mut stmt = db.conn.prepare(
                "SELECT id, name, channelType, isEnabled FROM publishingChannel ORDER BY name"
            ).map_err(|e| e.to_string())?;
            let channels: Vec<Value> = stmt.query_map([], |row| {
                Ok(json!({
                    "id": row.get::<_, String>(0)?,
                    "name": row.get::<_, String>(1)?,
                    "channelType": row.get::<_, String>(2)?,
                    "isEnabled": row.get::<_, i32>(3)? != 0
                }))
            }).map_err(|e| e.to_string())?
                .filter_map(|r| r.ok())
                .collect();
            Ok(json!({"channels": channels}).to_string())
        }

        _ => Err(format!("Unknown tool: {}", name)),
    }
}

fn str_arg(args: &Value, key: &str) -> Result<String, String> {
    args.get(key)
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| format!("Missing required argument: {}", key))
}
