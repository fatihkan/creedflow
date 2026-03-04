use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::Mutex;

/// Simple HTTP server for webhook triggers.
/// Routes: GET /api/status, POST /api/tasks
pub struct WebhookServer {
    port: u16,
    api_key: Option<String>,
    db: Arc<Mutex<crate::db::Database>>,
}

impl WebhookServer {
    pub fn new(port: u16, api_key: Option<String>, db: Arc<Mutex<crate::db::Database>>) -> Self {
        Self { port, api_key, db }
    }

    pub async fn run(self) {
        let addr = format!("127.0.0.1:{}", self.port);
        let listener = match TcpListener::bind(&addr).await {
            Ok(l) => l,
            Err(e) => {
                log::error!("Webhook server failed to bind to {}: {}", addr, e);
                return;
            }
        };
        log::info!("Webhook server listening on {}", addr);

        let api_key = self.api_key.clone();
        let db = self.db.clone();

        loop {
            let (mut stream, _) = match listener.accept().await {
                Ok(conn) => conn,
                Err(_) => continue,
            };

            let api_key = api_key.clone();
            let db = db.clone();

            tokio::spawn(async move {
                let mut buf = vec![0u8; 65536];
                let n = match stream.read(&mut buf).await {
                    Ok(n) => n,
                    Err(_) => return,
                };
                let request = String::from_utf8_lossy(&buf[..n]).to_string();

                let response = handle_request(&request, &api_key, &db).await;
                let _ = stream.write_all(response.as_bytes()).await;
                let _ = stream.shutdown().await;
            });
        }
    }
}

async fn handle_request(
    raw: &str,
    api_key: &Option<String>,
    db: &Arc<Mutex<crate::db::Database>>,
) -> String {
    let lines: Vec<&str> = raw.split("\r\n").collect();
    let request_line = match lines.first() {
        Some(l) => *l,
        None => return http_response(400, r#"{"error":"Bad request"}"#),
    };

    let parts: Vec<&str> = request_line.split_whitespace().collect();
    if parts.len() < 2 {
        return http_response(400, r#"{"error":"Bad request"}"#);
    }

    let method = parts[0];
    let path = parts[1];

    // Check API key
    if let Some(key) = api_key {
        if !key.is_empty() {
            let header_key = lines.iter()
                .find(|l| l.to_lowercase().starts_with("x-api-key:"))
                .map(|l| l["x-api-key:".len()..].trim());
            if header_key != Some(key.as_str()) {
                return http_response(401, r#"{"error":"Unauthorized"}"#);
            }
        }
    }

    match (method, path) {
        ("GET", "/api/status") => {
            http_response(200, r#"{"status":"ok","version":"1.5.0"}"#)
        }
        ("POST", "/api/tasks") => {
            // Extract body
            let body = raw.split("\r\n\r\n").nth(1).unwrap_or("");

            let req: serde_json::Value = match serde_json::from_str(body) {
                Ok(v) => v,
                Err(_) => return http_response(400, r#"{"error":"Invalid JSON body"}"#),
            };

            let project_id = req["projectId"].as_str().unwrap_or("");
            let title = req["title"].as_str().unwrap_or("Webhook Task");
            let description = req["description"].as_str().unwrap_or("");
            let agent_type = req["agentType"].as_str().unwrap_or("coder");

            if project_id.is_empty() || title.is_empty() {
                return http_response(400, r#"{"error":"projectId and title are required"}"#);
            }

            let task_id = uuid::Uuid::new_v4().to_string();
            let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S").to_string();

            let db_guard = db.lock().await;
            let result = db_guard.conn.execute(
                "INSERT INTO agentTask (id, projectId, title, description, agentType, status, priority, retryCount, maxRetries, createdAt, updatedAt) VALUES (?1, ?2, ?3, ?4, ?5, 'queued', 5, 0, 3, ?6, ?6)",
                rusqlite::params![task_id, project_id, title, description, agent_type, now],
            );

            match result {
                Ok(_) => {
                    let body = format!(r#"{{"taskId":"{}","status":"queued"}}"#, task_id);
                    http_response(201, &body)
                }
                Err(e) => {
                    let body = format!(r#"{{"error":"{}"}}"#, e);
                    http_response(500, &body)
                }
            }
        }
        _ => http_response(404, r#"{"error":"Not found"}"#),
    }
}

fn http_response(status: u16, body: &str) -> String {
    let status_text = match status {
        200 => "OK",
        201 => "Created",
        400 => "Bad Request",
        401 => "Unauthorized",
        404 => "Not Found",
        500 => "Internal Server Error",
        _ => "Unknown",
    };
    format!(
        "HTTP/1.1 {} {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        status, status_text, body.len(), body
    )
}
