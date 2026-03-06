use crate::db::Database;
use crate::db::models::{
    BackendType, HealthEvent, HealthStatus, HealthTargetType,
    NotificationCategory, NotificationSeverity,
};
use crate::services::notifications::NotificationService;
use chrono::Utc;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

// ─── Rate Limit Detector ────────────────────────────────────────────────────

/// Detects rate-limit signals in CLI error output.
pub struct RateLimitDetector;

impl RateLimitDetector {
    const PATTERNS: &'static [&'static str] = &[
        "429",
        "rate limit",
        "rate_limit",
        "too many requests",
        "RESOURCE_EXHAUSTED",
        "quota exceeded",
        "throttled",
        "overloaded",
    ];

    /// Check if the output contains rate-limit signals.
    pub fn detect(output: &str) -> Option<String> {
        let lower = output.to_lowercase();
        for pattern in Self::PATTERNS {
            if lower.contains(&pattern.to_lowercase()) {
                return Some(pattern.to_string());
            }
        }
        None
    }

    /// Exponential backoff for rate-limited retries: 60s * 2^retryCount, max 600s.
    pub fn backoff_interval(retry_count: i32) -> u64 {
        let base: u64 = 60;
        let multiplier = 2u64.pow(retry_count.max(0) as u32);
        (base * multiplier).min(600)
    }
}

// ─── Backend Health Monitor ─────────────────────────────────────────────────

/// Periodically checks all CLI backends for health by running `--version`.
pub struct BackendHealthMonitor {
    db: Arc<Mutex<Database>>,
    notification_service: Arc<NotificationService>,
    is_running: Arc<std::sync::atomic::AtomicBool>,
    polling_handle: Mutex<Option<tokio::task::JoinHandle<()>>>,
    current_status: Arc<Mutex<HashMap<String, HealthStatus>>>,
}

impl BackendHealthMonitor {
    pub fn new(db: Arc<Mutex<Database>>, notification_service: Arc<NotificationService>) -> Self {
        Self {
            db,
            notification_service,
            is_running: Arc::new(std::sync::atomic::AtomicBool::new(false)),
            polling_handle: Mutex::new(None),
            current_status: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn start(&self) {
        if self.is_running.load(std::sync::atomic::Ordering::SeqCst) {
            return;
        }
        self.is_running.store(true, std::sync::atomic::Ordering::SeqCst);

        let is_running = self.is_running.clone();
        let db = self.db.clone();
        let notif_service = self.notification_service.clone();
        let current_status = self.current_status.clone();

        let handle = tokio::spawn(async move {
            let mut last_status: HashMap<String, HealthStatus> = HashMap::new();

            while is_running.load(std::sync::atomic::Ordering::SeqCst) {
                let backends = vec![
                    (BackendType::Claude, "claude"),
                    (BackendType::Codex, "codex"),
                    (BackendType::Gemini, "gemini"),
                    (BackendType::Ollama, "ollama"),
                    (BackendType::LmStudio, "lmStudio"),
                    (BackendType::LlamaCpp, "llamaCpp"),
                    (BackendType::Mlx, "mlx"),
                    (BackendType::OpenCode, "opencode"),
                ];

                for (_backend_type, name) in &backends {
                    let start = std::time::Instant::now();
                    let status = check_backend_health(name).await;
                    let elapsed_ms = start.elapsed().as_millis() as i32;

                    let error_msg = if status == HealthStatus::Unhealthy {
                        Some(format!("Backend {} is not available", name))
                    } else {
                        None
                    };

                    // Record to DB
                    let event = HealthEvent {
                        id: Uuid::new_v4().to_string(),
                        target_type: HealthTargetType::Backend.as_str().to_string(),
                        target_name: name.to_string(),
                        status: status.as_str().to_string(),
                        response_time_ms: Some(elapsed_ms),
                        error_message: error_msg.clone(),
                        metadata: None,
                        checked_at: Utc::now().format("%Y-%m-%d %H:%M:%S").to_string(),
                    };
                    {
                        let db_lock = db.lock().await;
                        let _ = HealthEvent::insert(&db_lock.conn, &event);
                    }

                    // Update current status
                    {
                        let mut cs = current_status.lock().await;
                        cs.insert(name.to_string(), status.clone());
                    }

                    // Emit notification on transition
                    let previous = last_status.get(*name).cloned().unwrap_or(HealthStatus::Unknown);
                    if previous != status && !(previous == HealthStatus::Unknown && status == HealthStatus::Healthy) {
                        let (severity, title) = match &status {
                            HealthStatus::Healthy => (
                                NotificationSeverity::Success,
                                format!("Backend \"{}\" Recovered", name),
                            ),
                            HealthStatus::Degraded => (
                                NotificationSeverity::Warning,
                                format!("Backend \"{}\" Degraded", name),
                            ),
                            HealthStatus::Unhealthy => (
                                NotificationSeverity::Error,
                                format!("Backend \"{}\" Unhealthy", name),
                            ),
                            HealthStatus::Unknown => continue,
                        };
                        let msg = error_msg.unwrap_or_else(|| format!("Response time: {}ms", elapsed_ms));
                        notif_service.emit(
                            NotificationCategory::BackendHealth,
                            severity,
                            &title,
                            &msg,
                        ).await;
                    }
                    last_status.insert(name.to_string(), status);
                }

                tokio::time::sleep(tokio::time::Duration::from_secs(60)).await;
            }
        });

        *self.polling_handle.lock().await = Some(handle);
    }

    pub async fn stop(&self) {
        self.is_running.store(false, std::sync::atomic::Ordering::SeqCst);
        if let Some(handle) = self.polling_handle.lock().await.take() {
            handle.abort();
        }
    }

    pub async fn get_status(&self) -> HashMap<String, HealthStatus> {
        self.current_status.lock().await.clone()
    }
}

/// Check if a backend CLI binary is available by running `<cmd> --version`.
async fn check_backend_health(name: &str) -> HealthStatus {
    let cmd = match name {
        "claude" => "claude",
        "codex" => "codex",
        "gemini" => "gemini",
        "ollama" => "ollama",
        "opencode" => "opencode",
        "llamaCpp" => "llama-cli",
        "mlx" => "mlx_lm.generate",
        "lmStudio" => {
            // HTTP check for LM Studio
            return check_lmstudio_health().await;
        }
        _ => return HealthStatus::Unknown,
    };

    match tokio::time::timeout(
        tokio::time::Duration::from_secs(5),
        tokio::process::Command::new(cmd)
            .arg("--version")
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status(),
    ).await {
        Ok(Ok(status)) if status.success() => HealthStatus::Healthy,
        Ok(Ok(_)) => HealthStatus::Unhealthy,
        Ok(Err(_)) => HealthStatus::Unhealthy,
        Err(_) => HealthStatus::Unhealthy, // timeout
    }
}

async fn check_lmstudio_health() -> HealthStatus {
    match tokio::time::timeout(
        tokio::time::Duration::from_secs(5),
        reqwest::get("http://localhost:1234/v1/models"),
    ).await {
        Ok(Ok(resp)) if resp.status().is_success() => HealthStatus::Healthy,
        _ => HealthStatus::Unhealthy,
    }
}

// ─── MCP Health Monitor ─────────────────────────────────────────────────────

/// Periodically checks enabled MCP server configurations for health.
pub struct MCPHealthMonitor {
    db: Arc<Mutex<Database>>,
    notification_service: Arc<NotificationService>,
    is_running: Arc<std::sync::atomic::AtomicBool>,
    polling_handle: Mutex<Option<tokio::task::JoinHandle<()>>>,
    current_status: Arc<Mutex<HashMap<String, HealthStatus>>>,
}

impl MCPHealthMonitor {
    pub fn new(db: Arc<Mutex<Database>>, notification_service: Arc<NotificationService>) -> Self {
        Self {
            db,
            notification_service,
            is_running: Arc::new(std::sync::atomic::AtomicBool::new(false)),
            polling_handle: Mutex::new(None),
            current_status: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn start(&self) {
        if self.is_running.load(std::sync::atomic::Ordering::SeqCst) {
            return;
        }
        self.is_running.store(true, std::sync::atomic::Ordering::SeqCst);

        let is_running = self.is_running.clone();
        let db = self.db.clone();
        let notif_service = self.notification_service.clone();
        let current_status = self.current_status.clone();

        let handle = tokio::spawn(async move {
            let mut last_status: HashMap<String, HealthStatus> = HashMap::new();

            while is_running.load(std::sync::atomic::Ordering::SeqCst) {
                // Fetch enabled MCP configs
                let configs: Vec<(String, String, String, String)> = {
                    let db_lock = db.lock().await;
                    let mut stmt = db_lock.conn.prepare(
                        "SELECT name, command, arguments, environmentVars FROM mcpServerConfig WHERE isEnabled = 1"
                    ).map_err(|e| {
                        log::error!("Failed to prepare MCP query: {}", e);
                        e
                    }).unwrap_or_else(|_| {
                        // Return an empty statement result on failure
                        log::error!("MCP health monitor: skipping cycle due to DB error");
                        return db_lock.conn.prepare("SELECT NULL WHERE 0").expect("trivial query");
                    });
                    stmt.query_map([], |row| {
                        Ok((
                            row.get::<_, String>(0)?,
                            row.get::<_, String>(1)?,
                            row.get::<_, String>(2)?,
                            row.get::<_, String>(3)?,
                        ))
                    }).ok()
                    .map(|rows| rows.filter_map(|r| r.ok()).collect())
                    .unwrap_or_default()
                };

                for (name, command, args_json, env_json) in &configs {
                    let start = std::time::Instant::now();
                    let status = check_mcp_server_health(command, args_json, env_json).await;
                    let elapsed_ms = start.elapsed().as_millis() as i32;

                    let error_msg = if status == HealthStatus::Unhealthy {
                        Some(format!("MCP server {} is not responding", name))
                    } else {
                        None
                    };

                    // Record to DB
                    let event = HealthEvent {
                        id: Uuid::new_v4().to_string(),
                        target_type: HealthTargetType::Mcp.as_str().to_string(),
                        target_name: name.clone(),
                        status: status.as_str().to_string(),
                        response_time_ms: Some(elapsed_ms),
                        error_message: error_msg.clone(),
                        metadata: None,
                        checked_at: Utc::now().format("%Y-%m-%d %H:%M:%S").to_string(),
                    };
                    {
                        let db_lock = db.lock().await;
                        let _ = HealthEvent::insert(&db_lock.conn, &event);
                    }

                    // Update current status
                    {
                        let mut cs = current_status.lock().await;
                        cs.insert(name.clone(), status.clone());
                    }

                    // Emit notification on transition
                    let previous = last_status.get(name).cloned().unwrap_or(HealthStatus::Unknown);
                    if previous != status && !(previous == HealthStatus::Unknown && status == HealthStatus::Healthy) {
                        let (severity, title) = match &status {
                            HealthStatus::Healthy => (
                                NotificationSeverity::Success,
                                format!("MCP Server \"{}\" Recovered", name),
                            ),
                            HealthStatus::Degraded => (
                                NotificationSeverity::Warning,
                                format!("MCP Server \"{}\" Degraded", name),
                            ),
                            HealthStatus::Unhealthy => (
                                NotificationSeverity::Error,
                                format!("MCP Server \"{}\" Unhealthy", name),
                            ),
                            HealthStatus::Unknown => continue,
                        };
                        let msg = error_msg.unwrap_or_else(|| format!("Response time: {}ms", elapsed_ms));
                        notif_service.emit(
                            NotificationCategory::McpHealth,
                            severity,
                            &title,
                            &msg,
                        ).await;
                    }
                    last_status.insert(name.clone(), status);
                }

                tokio::time::sleep(tokio::time::Duration::from_secs(120)).await;
            }
        });

        *self.polling_handle.lock().await = Some(handle);
    }

    pub async fn stop(&self) {
        self.is_running.store(false, std::sync::atomic::Ordering::SeqCst);
        if let Some(handle) = self.polling_handle.lock().await.take() {
            handle.abort();
        }
    }

    pub async fn get_status(&self) -> HashMap<String, HealthStatus> {
        self.current_status.lock().await.clone()
    }
}

/// Check if an MCP server process can start and stay alive for 1 second.
async fn check_mcp_server_health(command: &str, args_json: &str, env_json: &str) -> HealthStatus {
    // Check if command binary exists
    let cmd_path = std::path::Path::new(command);
    if !cmd_path.exists() {
        // Try resolving via PATH using `which`
        let which_result = tokio::process::Command::new("which")
            .arg(command)
            .output()
            .await;
        match which_result {
            Ok(output) if output.status.success() => {}
            _ => return HealthStatus::Unhealthy,
        }
    }

    // Parse arguments
    let args: Vec<String> = serde_json::from_str(args_json).unwrap_or_default();

    // Parse environment variables
    let env_vars: HashMap<String, String> = serde_json::from_str(env_json).unwrap_or_default();

    // Spawn process
    let mut cmd = tokio::process::Command::new(command);
    for arg in &args {
        cmd.arg(arg);
    }
    for (key, value) in &env_vars {
        cmd.env(key, value);
    }
    cmd.stdout(std::process::Stdio::null());
    cmd.stderr(std::process::Stdio::null());

    match cmd.spawn() {
        Ok(mut child) => {
            // Wait 1 second, then check if still alive
            tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;

            match child.try_wait() {
                Ok(None) => {
                    // Still running — healthy
                    let _ = child.kill().await;
                    HealthStatus::Healthy
                }
                Ok(Some(_)) => {
                    // Exited before 1s — unhealthy
                    HealthStatus::Unhealthy
                }
                Err(_) => HealthStatus::Unhealthy,
            }
        }
        Err(_) => HealthStatus::Unhealthy,
    }
}
