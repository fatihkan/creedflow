//! CreedFlow MCP Server — stdio JSON-RPC transport
//!
//! Provides 13 tools and 5 resources for external MCP clients to interact
//! with CreedFlow projects, tasks, assets, and publishing channels.

mod protocol;
mod tools;
mod resources;

use protocol::{JsonRpcRequest, JsonRpcResponse};
use std::io::{self, BufRead, Write};

fn main() {
    eprintln!("CreedFlow MCP Server starting (stdio transport)...");

    let db_path = creedflow_desktop_lib::db::default_db_path();
    let db = match creedflow_desktop_lib::db::Database::open(&db_path) {
        Ok(db) => db,
        Err(e) => {
            eprintln!("Failed to open database: {}", e);
            std::process::exit(1);
        }
    };

    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut out = stdout.lock();

    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };

        let line = line.trim().to_string();
        if line.is_empty() {
            continue;
        }

        let request: JsonRpcRequest = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                let err_resp = JsonRpcResponse::error(
                    serde_json::Value::Null,
                    -32700,
                    &format!("Parse error: {}", e),
                );
                let _ = writeln!(out, "{}", serde_json::to_string(&err_resp).unwrap());
                let _ = out.flush();
                continue;
            }
        };

        let response = handle_request(&db, &request);
        if let Some(resp) = response {
            let _ = writeln!(out, "{}", serde_json::to_string(&resp).unwrap());
            let _ = out.flush();
        }
    }
}

fn handle_request(db: &creedflow_desktop_lib::db::Database, req: &JsonRpcRequest) -> Option<JsonRpcResponse> {
    let method = req.method.as_str();

    match method {
        // MCP lifecycle
        "initialize" => {
            Some(JsonRpcResponse::success(req.id.clone(), serde_json::json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {},
                    "resources": {}
                },
                "serverInfo": {
                    "name": "creedflow",
                    "version": "1.0.0"
                }
            })))
        }
        "initialized" => None, // notification, no response
        "ping" => Some(JsonRpcResponse::success(req.id.clone(), serde_json::json!({}))),

        // Tools
        "tools/list" => {
            Some(JsonRpcResponse::success(req.id.clone(), serde_json::json!({
                "tools": tools::list_tools()
            })))
        }
        "tools/call" => {
            let tool_name = req.params.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let arguments = req.params.get("arguments").cloned().unwrap_or(serde_json::json!({}));
            match tools::call_tool(db, tool_name, &arguments) {
                Ok(result) => Some(JsonRpcResponse::success(req.id.clone(), serde_json::json!({
                    "content": [{ "type": "text", "text": result }]
                }))),
                Err(e) => Some(JsonRpcResponse::success(req.id.clone(), serde_json::json!({
                    "content": [{ "type": "text", "text": e }],
                    "isError": true
                }))),
            }
        }

        // Resources
        "resources/list" => {
            Some(JsonRpcResponse::success(req.id.clone(), serde_json::json!({
                "resources": resources::list_resources()
            })))
        }
        "resources/read" => {
            let uri = req.params.get("uri").and_then(|v| v.as_str()).unwrap_or("");
            match resources::read_resource(db, uri) {
                Ok(content) => Some(JsonRpcResponse::success(req.id.clone(), serde_json::json!({
                    "contents": [{ "uri": uri, "mimeType": "application/json", "text": content }]
                }))),
                Err(e) => Some(JsonRpcResponse::error(req.id.clone(), -32602, &e)),
            }
        }

        _ => {
            Some(JsonRpcResponse::error(req.id.clone(), -32601, &format!("Method not found: {}", method)))
        }
    }
}
