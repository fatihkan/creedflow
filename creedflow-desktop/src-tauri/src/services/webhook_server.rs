use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::Mutex;

/// Simple HTTP server for webhook triggers and local dashboard.
/// Routes: GET /, GET /api/status, GET /api/projects, GET /api/projects/:id/tasks,
///         GET /api/costs/summary, GET /api/health,
///         POST /api/tasks, POST /api/webhooks/github
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

/// Extract API key from query string (?key=...)
fn get_query_param<'a>(path: &'a str, name: &str) -> Option<&'a str> {
    let query = path.split('?').nth(1)?;
    for pair in query.split('&') {
        let mut kv = pair.splitn(2, '=');
        if let (Some(k), Some(v)) = (kv.next(), kv.next()) {
            if k == name {
                return Some(v);
            }
        }
    }
    None
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
    let full_path = parts[1];
    // Strip query string for route matching
    let path = full_path.split('?').next().unwrap_or(full_path);

    // GitHub webhook path has its own auth (HMAC signature)
    let is_github_webhook = method == "POST" && path == "/api/webhooks/github";

    // Check API key for non-GitHub routes (header or query param)
    if !is_github_webhook {
        if let Some(key) = api_key {
            if !key.is_empty() {
                let header_key = get_header(&lines, "x-api-key");
                let query_key = get_query_param(full_path, "key");
                let authed = header_key == Some(key.as_str()) || query_key == Some(key.as_str());
                if !authed {
                    return http_response(401, r#"{"error":"Unauthorized"}"#);
                }
            }
        }
    }

    // Dashboard route
    if method == "GET" && (path == "/" || path == "/dashboard") {
        return html_response(200, DASHBOARD_HTML);
    }

    // Project tasks route: /api/projects/:id/tasks
    if method == "GET" && path.starts_with("/api/projects/") && path.ends_with("/tasks") {
        let segments: Vec<&str> = path.split('/').collect();
        // /api/projects/{id}/tasks -> ["", "api", "projects", "{id}", "tasks"]
        if segments.len() == 5 {
            let project_id = segments[3];
            return handle_project_tasks(db, project_id).await;
        }
    }

    match (method, path) {
        ("GET", "/api/status") => {
            http_response(200, r#"{"status":"ok","version":"1.5.0"}"#)
        }
        ("GET", "/api/projects") => {
            handle_list_projects(db).await
        }
        ("GET", "/api/costs/summary") => {
            handle_cost_summary(db).await
        }
        ("GET", "/api/health") => {
            handle_health(db).await
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

// MARK: - Dashboard API Handlers

async fn handle_list_projects(db: &Arc<Mutex<crate::db::Database>>) -> String {
    let db_guard = db.lock().await;
    let mut stmt = match db_guard.conn.prepare(
        "SELECT id, name, status, createdAt FROM project ORDER BY name"
    ) {
        Ok(s) => s,
        Err(e) => return http_response(500, &format!(r#"{{"error":"{}"}}"#, e)),
    };

    let rows_result = stmt.query_map([], |row| {
        let id: String = row.get(0)?;
        let name: String = row.get(1)?;
        let status: String = row.get(2)?;
        let created_at: String = row.get(3)?;
        Ok(format!(
            r#"{{"id":"{}","name":"{}","status":"{}","createdAt":"{}"}}"#,
            escape_json(&id),
            escape_json(&name),
            escape_json(&status),
            escape_json(&created_at)
        ))
    });

    let rows: Vec<String> = match rows_result {
        Ok(mapped) => mapped.filter_map(|r| r.ok()).collect(),
        Err(e) => return http_response(500, &format!(r#"{{"error":"{}"}}"#, e)),
    };

    let body = format!("[{}]", rows.join(","));
    http_response(200, &body)
}

async fn handle_project_tasks(db: &Arc<Mutex<crate::db::Database>>, project_id: &str) -> String {
    let db_guard = db.lock().await;
    let mut stmt = match db_guard.conn.prepare(
        "SELECT id, title, agentType, status, backend, durationMs, costUsd FROM agentTask WHERE projectId = ?1 ORDER BY createdAt DESC"
    ) {
        Ok(s) => s,
        Err(e) => return http_response(500, &format!(r#"{{"error":"{}"}}"#, e)),
    };

    let rows_result = stmt.query_map(rusqlite::params![project_id], |row| {
        let id: String = row.get(0)?;
        let title: String = row.get(1)?;
        let agent_type: String = row.get(2)?;
        let status: String = row.get(3)?;
        let backend: Option<String> = row.get(4)?;
        let duration_ms: Option<i64> = row.get(5)?;
        let cost_usd: Option<f64> = row.get(6)?;
        Ok(format!(
            r#"{{"id":"{}","title":"{}","agentType":"{}","status":"{}","backend":{},"durationMs":{},"costUsd":{}}}"#,
            escape_json(&id),
            escape_json(&title),
            escape_json(&agent_type),
            escape_json(&status),
            backend.map(|b| format!("\"{}\"", escape_json(&b))).unwrap_or_else(|| "null".to_string()),
            duration_ms.map(|d| d.to_string()).unwrap_or_else(|| "null".to_string()),
            cost_usd.map(|c| format!("{:.4}", c)).unwrap_or_else(|| "null".to_string()),
        ))
    });

    let rows: Vec<String> = match rows_result {
        Ok(mapped) => mapped.filter_map(|r| r.ok()).collect(),
        Err(e) => return http_response(500, &format!(r#"{{"error":"{}"}}"#, e)),
    };

    let body = format!("[{}]", rows.join(","));
    http_response(200, &body)
}

async fn handle_cost_summary(db: &Arc<Mutex<crate::db::Database>>) -> String {
    let db_guard = db.lock().await;
    let result = db_guard.conn.query_row(
        "SELECT COALESCE(SUM(costUsd), 0), COUNT(*), COALESCE(SUM(inputTokens + outputTokens), 0) FROM costTracking",
        [],
        |row| {
            let total_cost: f64 = row.get(0)?;
            let total_tasks: i64 = row.get(1)?;
            let total_tokens: i64 = row.get(2)?;
            Ok(format!(
                r#"{{"totalCost":{:.4},"totalTasks":{},"totalTokens":{}}}"#,
                total_cost, total_tasks, total_tokens
            ))
        },
    );

    match result {
        Ok(body) => http_response(200, &body),
        Err(_) => http_response(200, r#"{"totalCost":0,"totalTasks":0,"totalTokens":0}"#),
    }
}

async fn handle_health(db: &Arc<Mutex<crate::db::Database>>) -> String {
    let db_guard = db.lock().await;
    let mut stmt = match db_guard.conn.prepare(
        "SELECT targetName, status, errorMessage, checkedAt FROM healthEvent WHERE targetType = 'backend' ORDER BY checkedAt DESC"
    ) {
        Ok(s) => s,
        Err(_) => return http_response(200, r#"{"backends":[]}"#),
    };

    // Collect latest status per backend
    let mut seen = std::collections::HashSet::new();
    let mut rows: Vec<String> = Vec::new();

    let mapped = stmt.query_map([], |row| {
        let name: String = row.get(0)?;
        let status: String = row.get(1)?;
        let error: Option<String> = row.get(2)?;
        let checked_at: String = row.get(3)?;
        Ok((name, status, error, checked_at))
    });

    if let Ok(iter) = mapped {
        for r in iter.flatten() {
            if seen.insert(r.0.clone()) {
                rows.push(format!(
                    r#"{{"name":"{}","status":"{}","error":{},"checkedAt":"{}"}}"#,
                    escape_json(&r.0),
                    escape_json(&r.1),
                    r.2.map(|e| format!("\"{}\"", escape_json(&e))).unwrap_or_else(|| "null".to_string()),
                    escape_json(&r.3),
                ));
            }
        }
    }

    let body = format!(r#"{{"backends":[{}]}}"#, rows.join(","));
    http_response(200, &body)
}

/// Escape special characters for JSON string values
fn escape_json(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

fn http_response(status: u16, body: &str) -> String {
    let status_text = match status {
        200 => "OK",
        201 => "Created",
        400 => "Bad Request",
        401 => "Unauthorized",
        404 => "Not Found",
        413 => "Payload Too Large",
        500 => "Internal Server Error",
        _ => "Unknown",
    };
    format!(
        "HTTP/1.1 {} {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        status, status_text, body.len(), body
    )
}

fn html_response(status: u16, body: &str) -> String {
    let status_text = match status {
        200 => "OK",
        404 => "Not Found",
        _ => "Unknown",
    };
    format!(
        "HTTP/1.1 {} {}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        status, status_text, body.len(), body
    )
}

// MARK: - Embedded Dashboard HTML

const DASHBOARD_HTML: &str = r##"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CreedFlow Dashboard</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#18181b;color:#e4e4e7;min-height:100vh}
a{color:#a78bfa;text-decoration:none}
.header{background:#27272a;border-bottom:1px solid #3f3f46;padding:16px 24px;display:flex;align-items:center;justify-content:space-between}
.header h1{font-size:20px;font-weight:700;color:#f4f4f5}
.header .subtitle{font-size:13px;color:#71717a;margin-left:12px}
.header .refresh{font-size:12px;color:#71717a}
.container{max-width:1200px;margin:0 auto;padding:24px}
.grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px;margin-bottom:24px}
.card{background:#27272a;border:1px solid #3f3f46;border-radius:8px;padding:16px}
.card h3{font-size:13px;color:#a1a1aa;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:8px}
.card .value{font-size:28px;font-weight:700;color:#f4f4f5}
.card .unit{font-size:14px;color:#71717a;margin-left:4px}
.projects{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:24px}
.project-card{background:#27272a;border:1px solid #3f3f46;border-radius:8px;padding:16px;cursor:pointer;transition:border-color 0.15s}
.project-card:hover{border-color:#a78bfa}
.project-card.selected{border-color:#a78bfa;background:#2e1065}
.project-card .name{font-size:15px;font-weight:600;color:#f4f4f5;margin-bottom:4px}
.project-card .meta{font-size:12px;color:#71717a}
.badge{display:inline-block;padding:2px 8px;border-radius:9999px;font-size:11px;font-weight:600;text-transform:uppercase}
.badge-planning{background:#3b0764;color:#c084fc}
.badge-active{background:#064e3b;color:#6ee7b7}
.badge-in_progress,.badge-inProgress{background:#1e3a5f;color:#7dd3fc}
.badge-completed{background:#065f46;color:#6ee7b7}
.badge-queued{background:#422006;color:#fdba74}
.badge-passed{background:#065f46;color:#6ee7b7}
.badge-failed{background:#7f1d1d;color:#fca5a5}
.badge-needs_revision,.badge-needsRevision{background:#78350f;color:#fcd34d}
.badge-cancelled{background:#3f3f46;color:#a1a1aa}
.badge-healthy{background:#065f46;color:#6ee7b7}
.badge-unhealthy{background:#7f1d1d;color:#fca5a5}
.badge-unknown{background:#3f3f46;color:#a1a1aa}
table{width:100%;border-collapse:collapse}
th{text-align:left;padding:8px 12px;font-size:12px;color:#a1a1aa;text-transform:uppercase;letter-spacing:0.5px;border-bottom:1px solid #3f3f46}
td{padding:8px 12px;font-size:13px;border-bottom:1px solid #27272a}
.task-table{background:#27272a;border:1px solid #3f3f46;border-radius:8px;overflow:hidden}
.task-table .header-row{font-size:15px;font-weight:600;padding:12px 16px;border-bottom:1px solid #3f3f46;color:#f4f4f5;display:flex;align-items:center;justify-content:space-between}
.health-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:8px;margin-top:16px}
.health-item{background:#27272a;border:1px solid #3f3f46;border-radius:6px;padding:10px 12px;display:flex;align-items:center;gap:8px}
.health-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}
.health-dot.healthy{background:#6ee7b7}
.health-dot.unhealthy{background:#fca5a5}
.health-dot.unknown{background:#71717a}
.empty{text-align:center;padding:32px;color:#71717a;font-size:14px}
.section-title{font-size:16px;font-weight:600;color:#f4f4f5;margin-bottom:12px}
@media(max-width:768px){.grid{grid-template-columns:1fr}.projects{grid-template-columns:1fr}}
</style>
</head>
<body>
<div class="header">
  <div style="display:flex;align-items:baseline">
    <h1>CreedFlow Dashboard</h1>
    <span class="subtitle">Local Web Dashboard</span>
  </div>
  <span class="refresh" id="refresh-status">Auto-refresh: 30s</span>
</div>
<div class="container">
  <!-- Cost Summary -->
  <div class="grid" id="cost-grid">
    <div class="card"><h3>Total Cost</h3><div class="value" id="total-cost">-</div></div>
    <div class="card"><h3>Total Tasks</h3><div class="value" id="total-tasks">-</div></div>
    <div class="card"><h3>Total Tokens</h3><div class="value" id="total-tokens">-</div></div>
  </div>

  <!-- Projects -->
  <div class="section-title">Projects</div>
  <div class="projects" id="project-list"></div>

  <!-- Tasks Table -->
  <div id="task-section" style="display:none">
    <div class="task-table">
      <div class="header-row">
        <span id="task-title">Tasks</span>
        <span style="font-size:12px;color:#71717a;font-weight:400" id="task-count"></span>
      </div>
      <table>
        <thead><tr><th>Title</th><th>Agent</th><th>Status</th><th>Backend</th><th>Duration</th><th>Cost</th></tr></thead>
        <tbody id="task-body"></tbody>
      </table>
    </div>
  </div>
  <div id="task-empty" style="display:none" class="empty">Select a project to view its tasks</div>

  <!-- Health -->
  <div style="margin-top:24px">
    <div class="section-title">Backend Health</div>
    <div class="health-grid" id="health-grid"></div>
  </div>
</div>
<script>
(function(){
  const API_KEY = new URLSearchParams(window.location.search).get('key') || '';
  const headers = API_KEY ? {'X-API-Key': API_KEY} : {};
  let selectedProject = null;

  function apiFetch(path) {
    const sep = path.includes('?') ? '&' : '?';
    const url = API_KEY ? path + sep + 'key=' + encodeURIComponent(API_KEY) : path;
    return fetch(url, {headers}).then(r => r.json()).catch(() => null);
  }

  function formatCost(v) {
    if (v == null) return '-';
    return '$' + Number(v).toFixed(2);
  }

  function formatTokens(v) {
    if (v == null || v === 0) return '0';
    if (v >= 1000000) return (v / 1000000).toFixed(1) + 'M';
    if (v >= 1000) return (v / 1000).toFixed(1) + 'K';
    return String(v);
  }

  function formatDuration(ms) {
    if (ms == null) return '-';
    if (ms < 1000) return ms + 'ms';
    var s = ms / 1000;
    if (s < 60) return s.toFixed(1) + 's';
    return (s / 60).toFixed(1) + 'm';
  }

  function badgeClass(status) {
    return 'badge badge-' + (status || 'unknown').replace(/_/g, '');
  }

  async function loadCosts() {
    var data = await apiFetch('/api/costs/summary');
    if (!data) return;
    document.getElementById('total-cost').textContent = formatCost(data.totalCost);
    document.getElementById('total-tasks').textContent = String(data.totalTasks);
    document.getElementById('total-tokens').textContent = formatTokens(data.totalTokens);
  }

  async function loadProjects() {
    var data = await apiFetch('/api/projects');
    if (!data) return;
    var container = document.getElementById('project-list');
    if (data.length === 0) {
      container.innerHTML = '<div class="empty" style="grid-column:1/-1">No projects yet</div>';
      return;
    }
    container.innerHTML = data.map(function(p) {
      var sel = selectedProject === p.id ? ' selected' : '';
      return '<div class="project-card' + sel + '" data-id="' + p.id + '" onclick="window._selectProject(\'' + p.id + '\',\'' + p.name.replace(/'/g, "\\'") + '\')">' +
        '<div class="name">' + escapeHtml(p.name) + '</div>' +
        '<div class="meta"><span class="' + badgeClass(p.status) + '">' + p.status + '</span> &middot; ' + p.createdAt + '</div>' +
        '</div>';
    }).join('');
  }

  async function loadTasks(projectId, projectName) {
    var section = document.getElementById('task-section');
    var empty = document.getElementById('task-empty');
    if (!projectId) {
      section.style.display = 'none';
      empty.style.display = 'block';
      return;
    }
    var data = await apiFetch('/api/projects/' + projectId + '/tasks');
    if (!data) return;
    section.style.display = 'block';
    empty.style.display = 'none';
    document.getElementById('task-title').textContent = (projectName || 'Project') + ' Tasks';
    document.getElementById('task-count').textContent = data.length + ' tasks';
    var tbody = document.getElementById('task-body');
    if (data.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:#71717a;padding:24px">No tasks</td></tr>';
      return;
    }
    tbody.innerHTML = data.map(function(t) {
      return '<tr>' +
        '<td>' + escapeHtml(t.title) + '</td>' +
        '<td>' + (t.agentType || '-') + '</td>' +
        '<td><span class="' + badgeClass(t.status) + '">' + (t.status || '-') + '</span></td>' +
        '<td>' + (t.backend || '-') + '</td>' +
        '<td>' + formatDuration(t.durationMs) + '</td>' +
        '<td>' + formatCost(t.costUsd) + '</td>' +
        '</tr>';
    }).join('');
  }

  async function loadHealth() {
    var data = await apiFetch('/api/health');
    if (!data || !data.backends) return;
    var grid = document.getElementById('health-grid');
    if (data.backends.length === 0) {
      grid.innerHTML = '<div class="empty">No health data</div>';
      return;
    }
    grid.innerHTML = data.backends.map(function(b) {
      return '<div class="health-item">' +
        '<div class="health-dot ' + (b.status || 'unknown') + '"></div>' +
        '<div><div style="font-size:13px;font-weight:600">' + escapeHtml(b.name) + '</div>' +
        '<div style="font-size:11px;color:#71717a">' + (b.status || 'unknown') + '</div></div>' +
        '</div>';
    }).join('');
  }

  function escapeHtml(s) {
    if (!s) return '';
    return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  window._selectProject = function(id, name) {
    selectedProject = id;
    loadProjects();
    loadTasks(id, name);
  };

  async function refresh() {
    await Promise.all([loadCosts(), loadProjects(), loadHealth()]);
    if (selectedProject) {
      var card = document.querySelector('.project-card[data-id="' + selectedProject + '"]');
      var name = card ? card.querySelector('.name').textContent : '';
      await loadTasks(selectedProject, name);
    }
  }

  refresh();
  setInterval(refresh, 30000);
})();
</script>
</body>
</html>"##;
