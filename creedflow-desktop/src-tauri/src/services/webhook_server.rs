use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::Mutex;

/// Simple HTTP server for webhook triggers.
/// Routes: GET /api/status, POST /api/tasks, POST /api/webhooks/github
pub struct WebhookServer {
    port: u16,
    api_key: Option<String>,
    github_secret: Option<String>,
    db: Arc<Mutex<crate::db::Database>>,
}

impl WebhookServer {
    pub fn new(port: u16, api_key: Option<String>, db: Arc<Mutex<crate::db::Database>>) -> Self {
        Self { port, api_key, github_secret: None, db }
    }

    pub fn with_github_secret(mut self, secret: Option<String>) -> Self {
        self.github_secret = secret;
        self
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
        let github_secret = self.github_secret.clone();
        let db = self.db.clone();

        loop {
            let (mut stream, _) = match listener.accept().await {
                Ok(conn) => conn,
                Err(_) => continue,
            };

            let api_key = api_key.clone();
            let github_secret = github_secret.clone();
            let db = db.clone();

            tokio::spawn(async move {
                const MAX_PAYLOAD: usize = 1_048_576; // 1MB max
                let mut buf = Vec::with_capacity(65536);
                let mut tmp = [0u8; 8192];
                loop {
                    match stream.read(&mut tmp).await {
                        Ok(0) => break,
                        Ok(n) => {
                            buf.extend_from_slice(&tmp[..n]);
                            if buf.len() > MAX_PAYLOAD {
                                let resp = http_response(413, r#"{"error":"Payload too large"}"#);
                                let _ = stream.write_all(resp.as_bytes()).await;
                                let _ = stream.shutdown().await;
                                return;
                            }
                            // If we've read the full HTTP request (headers + body), break
                            // Simple heuristic: check if we have \r\n\r\n (end of headers)
                            if buf.windows(4).any(|w| w == b"\r\n\r\n") {
                                // Check Content-Length to see if we have the full body
                                let text = String::from_utf8_lossy(&buf);
                                if let Some(cl) = get_content_length(&text) {
                                    let header_end = text.find("\r\n\r\n").unwrap_or(0) + 4;
                                    if buf.len() >= header_end + cl {
                                        break;
                                    }
                                } else {
                                    break; // No Content-Length, assume complete
                                }
                            }
                        }
                        Err(_) => return,
                    }
                }
                let request = String::from_utf8_lossy(&buf).to_string();

                let response = handle_request(&request, &api_key, &github_secret, &db).await;
                let _ = stream.write_all(response.as_bytes()).await;
                let _ = stream.shutdown().await;
            });
        }
    }
}

fn get_content_length(raw: &str) -> Option<usize> {
    for line in raw.split("\r\n") {
        if line.to_lowercase().starts_with("content-length:") {
            return line[15..].trim().parse().ok();
        }
    }
    None
}

fn get_header<'a>(lines: &'a [&str], name: &str) -> Option<&'a str> {
    let lower = name.to_lowercase();
    lines.iter()
        .find(|l| l.to_lowercase().starts_with(&format!("{}:", lower)))
        .map(|l| l[name.len() + 1..].trim())
}

fn verify_github_signature(secret: &str, body: &str, signature: &str) -> bool {
    use hmac::{Hmac, Mac};
    use sha2::Sha256;

    // signature format: sha256=<hex>
    let hex_sig = match signature.strip_prefix("sha256=") {
        Some(h) => h,
        None => return false,
    };

    // Decode the provided hex signature
    let provided_sig = match hex::decode(hex_sig) {
        Ok(s) => s,
        Err(_) => return false,
    };

    // Compute HMAC-SHA256
    let mut mac = Hmac::<Sha256>::new_from_slice(secret.as_bytes())
        .expect("HMAC accepts any key length");
    mac.update(body.as_bytes());

    // Constant-time comparison via hmac crate's verify_slice
    mac.verify_slice(&provided_sig).is_ok()
}

async fn handle_request(
    raw: &str,
    api_key: &Option<String>,
    github_secret: &Option<String>,
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

    // GitHub webhook path has its own auth (HMAC signature)
    let is_github_webhook = method == "POST" && path == "/api/webhooks/github";

    // Check API key for non-GitHub routes
    if !is_github_webhook {
        if let Some(key) = api_key {
            if !key.is_empty() {
                let header_key = get_header(&lines, "x-api-key");
                if header_key != Some(key.as_str()) {
                    return http_response(401, r#"{"error":"Unauthorized"}"#);
                }
            }
        }
    }

    match (method, path) {
        ("GET", "/api/status") => {
            http_response(200, r#"{"status":"ok","version":"1.5.0"}"#)
        }
        ("POST", "/api/tasks") => {
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
        ("POST", "/api/webhooks/github") => {
            let body = raw.split("\r\n\r\n").nth(1).unwrap_or("");

            // Validate GitHub signature if secret is configured
            if let Some(secret) = github_secret {
                if !secret.is_empty() {
                    let signature = get_header(&lines, "x-hub-signature-256").unwrap_or("");
                    if signature.is_empty() || !verify_github_signature(secret, body, signature) {
                        return http_response(401, r#"{"error":"Invalid signature"}"#);
                    }
                }
            }

            let event_type = get_header(&lines, "x-github-event").unwrap_or("");
            let payload: serde_json::Value = match serde_json::from_str(body) {
                Ok(v) => v,
                Err(_) => return http_response(400, r#"{"error":"Invalid JSON body"}"#),
            };

            // Find the first project to associate with (by repository name match)
            let repo_name = payload["repository"]["name"].as_str().unwrap_or("");
            let repo_full = payload["repository"]["full_name"].as_str().unwrap_or("");

            let db_guard = db.lock().await;

            // Try to find a matching project
            let project_id: Option<String> = db_guard.conn
                .query_row(
                    "SELECT id FROM project WHERE name = ?1 OR directoryPath LIKE ?2 LIMIT 1",
                    rusqlite::params![repo_name, format!("%/{}", repo_name)],
                    |row| row.get(0),
                )
                .ok();

            let project_id = match project_id {
                Some(id) => id,
                None => {
                    let body = format!(
                        r#"{{"status":"ignored","reason":"No matching project for repo: {}"}}"#,
                        repo_full
                    );
                    return http_response(200, &body);
                }
            };

            match event_type {
                "push" => {
                    // Auto-create analyzer task for push events
                    let branch = payload["ref"].as_str().unwrap_or("").replace("refs/heads/", "");
                    let commits_count = payload["commits"].as_array().map(|a| a.len()).unwrap_or(0);
                    let pusher = payload["pusher"]["name"].as_str().unwrap_or("unknown");

                    let task_id = uuid::Uuid::new_v4().to_string();
                    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S").to_string();
                    let title = format!("Analyze push to {} ({} commits by {})", branch, commits_count, pusher);
                    let description = format!(
                        "Triggered by GitHub push webhook. Branch: {}, Commits: {}, Pusher: {}, Repo: {}",
                        branch, commits_count, pusher, repo_full
                    );

                    let result = db_guard.conn.execute(
                        "INSERT INTO agentTask (id, projectId, title, description, agentType, status, priority, retryCount, maxRetries, createdAt, updatedAt) VALUES (?1, ?2, ?3, ?4, 'analyzer', 'queued', 5, 0, 3, ?5, ?5)",
                        rusqlite::params![task_id, project_id, title, description, now],
                    );

                    match result {
                        Ok(_) => {
                            log::info!("GitHub push webhook: created analyzer task {} for {}", task_id, repo_full);
                            let body = format!(r#"{{"taskId":"{}","event":"push","status":"queued"}}"#, task_id);
                            http_response(201, &body)
                        }
                        Err(e) => {
                            let body = format!(r#"{{"error":"{}"}}"#, e);
                            http_response(500, &body)
                        }
                    }
                }
                "pull_request" => {
                    // Auto-create reviewer task for PR events
                    let action = payload["action"].as_str().unwrap_or("");
                    if action != "opened" && action != "synchronize" && action != "reopened" {
                        return http_response(200, r#"{"status":"ignored","reason":"PR action not relevant"}"#);
                    }

                    let pr_number = payload["pull_request"]["number"].as_i64().unwrap_or(0);
                    let pr_title = payload["pull_request"]["title"].as_str().unwrap_or("Untitled PR");
                    let pr_branch = payload["pull_request"]["head"]["ref"].as_str().unwrap_or("unknown");

                    let task_id = uuid::Uuid::new_v4().to_string();
                    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S").to_string();
                    let title = format!("Review PR #{}: {}", pr_number, pr_title);
                    let description = format!(
                        "Triggered by GitHub pull_request webhook. PR #{}: {}, Branch: {}, Action: {}, Repo: {}",
                        pr_number, pr_title, pr_branch, action, repo_full
                    );

                    let result = db_guard.conn.execute(
                        "INSERT INTO agentTask (id, projectId, title, description, agentType, status, priority, retryCount, maxRetries, createdAt, updatedAt) VALUES (?1, ?2, ?3, ?4, 'reviewer', 'queued', 7, 0, 3, ?5, ?5)",
                        rusqlite::params![task_id, project_id, title, description, now],
                    );

                    match result {
                        Ok(_) => {
                            log::info!("GitHub PR webhook: created reviewer task {} for PR #{}", task_id, pr_number);
                            let body = format!(r#"{{"taskId":"{}","event":"pull_request","prNumber":{},"status":"queued"}}"#, task_id, pr_number);
                            http_response(201, &body)
                        }
                        Err(e) => {
                            let body = format!(r#"{{"error":"{}"}}"#, e);
                            http_response(500, &body)
                        }
                    }
                }
                _ => {
                    let body = format!(r#"{{"status":"ignored","event":"{}"}}"#, event_type);
                    http_response(200, &body)
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
