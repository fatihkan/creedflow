use crate::backends::{
    BackendRouter, CliBackend,
    claude::ClaudeBackend,
    codex::CodexBackend,
    gemini::GeminiBackend,
    ollama::OllamaBackend,
    lmstudio::LMStudioBackend,
    llamacpp::LlamaCppBackend,
    mlx::MLXBackend,
};
use crate::db::Database;
use crate::db::models::{AgentTask, AgentType};
use crate::engine::runner::{TaskRunner, TaskRunResult};
use crate::engine::scheduler::AgentScheduler;
use crate::engine::task_queue::TaskQueue;
use crate::engine::retry::RetryPolicy;
use crate::services::git_branch_manager::GitBranchManager;
use crate::services::telegram::TelegramService;
use crate::util::ndjson::extract_json;
use rusqlite::params;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::Emitter;
use tokio::sync::Mutex;
use tokio::time::{interval, Duration};

/// Central orchestration loop — polls TaskQueue every 2 seconds,
/// selects backend via BackendRouter, dispatches tasks to agents.
pub struct Orchestrator {
    db: Arc<Mutex<Database>>,
    task_queue: Arc<TaskQueue>,
    scheduler: Arc<AgentScheduler>,
    retry_policy: RetryPolicy,
    router: Arc<BackendRouter>,
    is_running: Arc<AtomicBool>,
    polling_handle: Mutex<Option<tokio::task::JoinHandle<()>>>,
    app_handle: Option<tauri::AppHandle>,
    telegram: Option<Arc<TelegramService>>,
}

impl Orchestrator {
    pub fn new(
        db: Arc<Mutex<Database>>,
        max_concurrency: usize,
        app_handle: Option<tauri::AppHandle>,
    ) -> Self {
        let task_queue = Arc::new(TaskQueue::new(db.clone()));
        let scheduler = Arc::new(AgentScheduler::new(max_concurrency));

        // Initialize all backends
        let backends: Vec<Box<dyn CliBackend>> = vec![
            Box::new(ClaudeBackend::new()),
            Box::new(CodexBackend::new()),
            Box::new(GeminiBackend::new()),
            Box::new(OllamaBackend::new()),
            Box::new(LMStudioBackend::new()),
            Box::new(LlamaCppBackend::new()),
            Box::new(MLXBackend::new()),
        ];
        let router = Arc::new(BackendRouter::new(backends));

        Self {
            db: db.clone(),
            task_queue,
            scheduler,
            retry_policy: RetryPolicy::default(),
            router,
            is_running: Arc::new(AtomicBool::new(false)),
            polling_handle: Mutex::new(None),
            app_handle,
            telegram: None,
        }
    }

    /// Configure Telegram notifications.
    pub fn set_telegram(&mut self, bot_token: String, chat_id: String) {
        self.telegram = Some(Arc::new(TelegramService::new(bot_token, chat_id)));
    }

    /// Start the orchestrator polling loop.
    pub async fn start(&self) -> Result<(), String> {
        if self.is_running.load(Ordering::SeqCst) {
            return Ok(());
        }

        // Recover orphaned tasks from previous crash
        self.task_queue.recover_orphaned_tasks().await?;

        self.is_running.store(true, Ordering::SeqCst);

        let is_running = self.is_running.clone();
        let task_queue = self.task_queue.clone();
        let scheduler = self.scheduler.clone();
        let app_handle = self.app_handle.clone();
        let db = self.db.clone();
        let router = self.router.clone();
        let retry_policy = RetryPolicy::default();
        let telegram = self.telegram.clone();

        let handle = tokio::spawn(async move {
            let mut tick = interval(Duration::from_secs(2));

            while is_running.load(Ordering::SeqCst) {
                tick.tick().await;

                // Try to dequeue a task
                match task_queue.dequeue().await {
                    Ok(Some(task)) => {
                        // Try to acquire a concurrency slot
                        if let Some(permit) = scheduler.try_acquire() {
                            log::info!("Dispatching task {} ({})", task.id, task.agent_type);

                            // Emit event to frontend
                            if let Some(ref handle) = app_handle {
                                let _ = handle.emit("task-status-changed", serde_json::json!({
                                    "taskId": task.id,
                                    "status": "in_progress",
                                    "agentType": task.agent_type,
                                }));
                            }

                            // Spawn task execution in background
                            let task_queue_c = task_queue.clone();
                            let db_c = db.clone();
                            let router_c = router.clone();
                            let app_handle_c = app_handle.clone();
                            let telegram_c = telegram.clone();

                            tokio::spawn(async move {
                                // Build revision memory if this is a retry
                                let revision_memory = if task.retry_count > 0 || task.revision_prompt.is_some() {
                                    Some(build_revision_memory(&task, &db_c).await)
                                } else {
                                    None
                                };

                                // Phase 3: Execute via TaskRunner
                                let result = TaskRunner::run(
                                    &task,
                                    &router_c,
                                    &db_c,
                                    app_handle_c.as_ref(),
                                    revision_memory,
                                ).await;

                                // Handle result
                                if result.success {
                                    // Write result to DB
                                    update_task_success(&task, &result, &db_c).await;

                                    // Record cost
                                    record_cost(&task, &result, &db_c).await;

                                    // Agent-specific completion handlers
                                    handle_agent_completion(&task, &result, &db_c, app_handle_c.as_ref()).await;

                                    // Git completion pipeline
                                    handle_git_completion(&task, &db_c, app_handle_c.as_ref()).await;

                                    // Telegram notification
                                    if let Some(ref tg) = telegram_c {
                                        let msg = format!(
                                            "✅ Task completed: {} ({})\nBackend: {}",
                                            task.title, task.agent_type, result.backend_type
                                        );
                                        let _ = tg.send_message(&msg).await;
                                    }
                                } else {
                                    let error_msg = result.error.unwrap_or_else(|| "Unknown error".to_string());
                                    log::error!("Task {} failed: {}", task.id, error_msg);

                                    // Check retry policy
                                    if retry_policy.should_retry(task.retry_count) {
                                        log::info!("Requeueing task {} (retry {})", task.id, task.retry_count + 1);
                                        let _ = task_queue_c.requeue(&task.id).await;
                                    } else {
                                        let _ = task_queue_c.fail(&task.id, &error_msg).await;

                                        // Telegram notification for failure
                                        if let Some(ref tg) = telegram_c {
                                            let msg = format!(
                                                "❌ Task failed: {} ({})\nError: {}",
                                                task.title, task.agent_type, error_msg
                                            );
                                            let _ = tg.send_message(&msg).await;
                                        }
                                    }

                                    // Emit failure to frontend
                                    if let Some(ref handle) = app_handle_c {
                                        let _ = handle.emit("task-status-changed", serde_json::json!({
                                            "taskId": task.id,
                                            "status": "failed",
                                            "agentType": task.agent_type,
                                            "error": error_msg,
                                        }));
                                    }
                                }

                                // Release concurrency slot
                                drop(permit);
                            });
                        } else {
                            // No slot available — defer (don't count as retry)
                            let _ = task_queue.defer_task(&task.id).await;
                            log::debug!("No scheduler slot, deferring task {}", task.id);
                        }
                    }
                    Ok(None) => {
                        // No tasks ready
                    }
                    Err(e) => {
                        log::error!("TaskQueue dequeue error: {}", e);
                    }
                }
            }
        });

        *self.polling_handle.lock().await = Some(handle);
        Ok(())
    }

    /// Stop the orchestrator.
    pub async fn stop(&self) {
        self.is_running.store(false, Ordering::SeqCst);
        if let Some(handle) = self.polling_handle.lock().await.take() {
            handle.abort();
        }
    }

    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::SeqCst)
    }
}

// ─── Helper Functions ────────────────────────────────────────────────────────

/// Build revision memory from previous attempts — reviews, errors, prior output.
async fn build_revision_memory(task: &AgentTask, db: &Arc<Mutex<Database>>) -> String {
    let mut memory = String::new();

    let db_lock = db.lock().await;

    // Previous reviews for this task
    let mut stmt = db_lock.conn.prepare(
        "SELECT score, verdict, summary, issues, suggestions FROM review WHERE taskId = ?1 ORDER BY createdAt DESC LIMIT 3"
    ).ok();

    if let Some(ref mut s) = stmt {
        if let Ok(rows) = s.query_map(params![task.id], |row| {
            Ok((
                row.get::<_, f64>(0).unwrap_or(0.0),
                row.get::<_, String>(1).unwrap_or_default(),
                row.get::<_, String>(2).unwrap_or_default(),
                row.get::<_, Option<String>>(3).unwrap_or(None),
                row.get::<_, Option<String>>(4).unwrap_or(None),
            ))
        }) {
            for row in rows.flatten() {
                memory.push_str(&format!(
                    "Previous review (score: {:.1}, verdict: {}):\n{}\n",
                    row.0, row.1, row.2
                ));
                if let Some(issues) = row.3 {
                    memory.push_str(&format!("Issues: {}\n", issues));
                }
                if let Some(suggestions) = row.4 {
                    memory.push_str(&format!("Suggestions: {}\n", suggestions));
                }
                memory.push('\n');
            }
        }
    }

    // Previous error message
    if let Some(ref err) = task.error_message {
        memory.push_str(&format!("Previous error: {}\n\n", err));
    }

    // Previous output (truncated)
    if let Some(ref result) = task.result {
        let truncated = if result.len() > 2000 {
            &result[..2000]
        } else {
            result
        };
        memory.push_str(&format!("Previous output (truncated):\n{}\n\n", truncated));
    }

    // User revision prompt
    if let Some(ref revision) = task.revision_prompt {
        memory.push_str(&format!("User revision instructions:\n{}\n", revision));
    }

    memory
}

/// Update task to passed status with result data.
async fn update_task_success(task: &AgentTask, result: &TaskRunResult, db: &Arc<Mutex<Database>>) {
    let db_lock = db.lock().await;
    let _ = db_lock.conn.execute(
        "UPDATE agentTask SET status = 'passed', result = ?2, costUSD = ?3, durationMs = ?4, sessionId = ?5, completedAt = datetime('now'), updatedAt = datetime('now') WHERE id = ?1",
        params![task.id, result.output, result.cost_usd, result.duration_ms, result.session_id],
    );
}

/// Record cost tracking entry.
async fn record_cost(task: &AgentTask, result: &TaskRunResult, db: &Arc<Mutex<Database>>) {
    if result.cost_usd.is_none() && result.input_tokens.is_none() {
        return;
    }

    let db_lock = db.lock().await;
    let id = uuid::Uuid::new_v4().to_string();
    let _ = db_lock.conn.execute(
        "INSERT INTO costTracking (id, projectId, taskId, agentType, inputTokens, outputTokens, costUSD, model, sessionId, backend, createdAt)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, datetime('now'))",
        params![
            id,
            task.project_id,
            task.id,
            task.agent_type,
            result.input_tokens.unwrap_or(0),
            result.output_tokens.unwrap_or(0),
            result.cost_usd.unwrap_or(0.0),
            result.model.as_deref().unwrap_or("unknown"),
            result.session_id,
            result.backend_type,
        ],
    );
}

/// Agent-specific completion handlers.
async fn handle_agent_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
    app_handle: Option<&tauri::AppHandle>,
) {
    let agent_type = AgentType::from_str(&task.agent_type);

    match agent_type {
        AgentType::Analyzer => handle_analyzer_completion(task, result, db).await,
        AgentType::Coder => handle_coder_completion(task, result, db).await,
        AgentType::Reviewer => handle_reviewer_completion(task, result, db, app_handle).await,
        AgentType::Designer | AgentType::ImageGenerator | AgentType::VideoEditor => {
            handle_creative_completion(task, result, db).await;
        }
        AgentType::Publisher => handle_publisher_completion(task, result, db).await,
        _ => {} // Tester, DevOps, Monitor, ContentWriter — no special handling
    }
}

/// Analyzer: parse JSON output → create features + tasks in DB.
async fn handle_analyzer_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
) {
    let json = match extract_json(&result.output) {
        Some(j) => j,
        None => {
            log::warn!("Analyzer output is not valid JSON for task {}", task.id);
            return;
        }
    };

    let features = match json.get("features").and_then(|f| f.as_array()) {
        Some(f) => f,
        None => {
            log::warn!("Analyzer output missing 'features' array");
            return;
        }
    };

    let db_lock = db.lock().await;

    for feature_json in features {
        let feature_id = uuid::Uuid::new_v4().to_string();
        let name = feature_json.get("name").and_then(|n| n.as_str()).unwrap_or("Unnamed Feature");
        let description = feature_json.get("description").and_then(|d| d.as_str()).unwrap_or("");
        let priority = feature_json.get("priority").and_then(|p| p.as_i64()).unwrap_or(5) as i32;

        let _ = db_lock.conn.execute(
            "INSERT INTO feature (id, projectId, name, description, priority, status, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, 'pending', datetime('now'), datetime('now'))",
            params![feature_id, task.project_id, name, description, priority],
        );

        if let Some(tasks) = feature_json.get("tasks").and_then(|t| t.as_array()) {
            let mut task_ids: Vec<(String, String)> = Vec::new(); // (title, id) for dependency resolution

            for task_json in tasks {
                let task_id = uuid::Uuid::new_v4().to_string();
                let title = task_json.get("title").and_then(|t| t.as_str()).unwrap_or("Unnamed Task");
                let desc = task_json.get("description").and_then(|d| d.as_str()).unwrap_or("");
                let agent = task_json.get("agentType").and_then(|a| a.as_str()).unwrap_or("coder");
                let prio = task_json.get("priority").and_then(|p| p.as_i64()).unwrap_or(5) as i32;

                let _ = db_lock.conn.execute(
                    "INSERT INTO agentTask (id, projectId, featureId, agentType, title, description, priority, status, retryCount, maxRetries, createdAt, updatedAt)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'queued', 0, 3, datetime('now'), datetime('now'))",
                    params![task_id, task.project_id, feature_id, agent, title, desc, prio],
                );

                task_ids.push((title.to_string(), task_id.clone()));

                // Handle dependencies
                if let Some(deps) = task_json.get("dependencies").and_then(|d| d.as_array()) {
                    for dep in deps {
                        if let Some(dep_title) = dep.as_str() {
                            // Find the task ID by title
                            if let Some((_, dep_id)) = task_ids.iter().find(|(t, _)| t == dep_title) {
                                let _ = db_lock.conn.execute(
                                    "INSERT OR IGNORE INTO taskDependency (taskId, dependsOnTaskId) VALUES (?1, ?2)",
                                    params![task_id, dep_id],
                                );
                            }
                        }
                    }
                }
            }
        }

        log::info!("Created feature '{}' with tasks for project {}", name, task.project_id);
    }

    // Update project status to in_progress
    let _ = db_lock.conn.execute(
        "UPDATE project SET status = 'in_progress', updatedAt = datetime('now') WHERE id = ?1",
        params![task.project_id],
    );
}

/// Coder: extract branchName and prNumber from result, update task.
async fn handle_coder_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
) {
    // Setup feature branch if not already done
    let dir = {
        let db_lock = db.lock().await;
        let d: Option<String> = db_lock.conn.query_row(
            "SELECT directoryPath FROM project WHERE id = ?1",
            [&task.project_id],
            |row| row.get(0),
        ).ok();
        d.filter(|d| !d.is_empty())
    };

    if let Some(dir) = dir {
        // Try to extract branch name from output
        if let Some(json) = extract_json(&result.output) {
            let branch = json.get("branchName").and_then(|b| b.as_str());
            let pr_number = json.get("prNumber").and_then(|p| p.as_i64()).map(|p| p as i32);

            if branch.is_some() || pr_number.is_some() {
                let db_lock = db.lock().await;
                let _ = db_lock.conn.execute(
                    "UPDATE agentTask SET branchName = COALESCE(?2, branchName), prNumber = COALESCE(?3, prNumber), updatedAt = datetime('now') WHERE id = ?1",
                    params![task.id, branch, pr_number],
                );
            }
        }

        // If no branch was set, try setting up one and committing
        let task_branch = {
            let db_lock = db.lock().await;
            db_lock.conn.query_row(
                "SELECT branchName FROM agentTask WHERE id = ?1",
                [&task.id],
                |row| row.get::<_, Option<String>>(0),
            ).ok().flatten()
        };

        if task_branch.is_none() {
            if let Ok(branch) = GitBranchManager::setup_feature_branch(&dir, &task.id, &task.title).await {
                let db_lock = db.lock().await;
                let _ = db_lock.conn.execute(
                    "UPDATE agentTask SET branchName = ?2, updatedAt = datetime('now') WHERE id = ?1",
                    params![task.id, branch],
                );
            }
        }

        // Queue a review task for the coder's work
        let review_task_id = uuid::Uuid::new_v4().to_string();
        let db_lock = db.lock().await;
        let _ = db_lock.conn.execute(
            "INSERT INTO agentTask (id, projectId, featureId, agentType, title, description, priority, status, retryCount, maxRetries, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, 'reviewer', ?4, ?5, ?6, 'queued', 0, 3, datetime('now'), datetime('now'))",
            params![
                review_task_id,
                task.project_id,
                task.feature_id,
                format!("Review: {}", task.title),
                format!("Review the code changes for task: {}", task.description),
                task.priority,
            ],
        );
        // Add dependency: review depends on coder
        let _ = db_lock.conn.execute(
            "INSERT OR IGNORE INTO taskDependency (taskId, dependsOnTaskId) VALUES (?1, ?2)",
            params![review_task_id, task.id],
        );
    }
}

/// Reviewer: parse score/verdict, create Review record, update task status.
async fn handle_reviewer_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
    app_handle: Option<&tauri::AppHandle>,
) {
    let json = match extract_json(&result.output) {
        Some(j) => j,
        None => {
            log::warn!("Reviewer output is not valid JSON for task {}", task.id);
            return;
        }
    };

    let score = json.get("score").and_then(|s| s.as_f64()).unwrap_or(0.0);
    let _verdict_str = json.get("verdict").and_then(|v| v.as_str()).unwrap_or("fail");
    let summary = json.get("summary").and_then(|s| s.as_str()).unwrap_or("");
    let issues = json.get("issues").and_then(|i| i.as_str());
    let suggestions = json.get("suggestions").and_then(|s| s.as_str());
    let security_notes = json.get("securityNotes").and_then(|s| s.as_str());

    // Determine verdict: >= 7.0 PASS, 5.0-6.9 NEEDS_REVISION, < 5.0 FAIL
    let verdict = if score >= 7.0 {
        "pass"
    } else if score >= 5.0 {
        "needsRevision"
    } else {
        "fail"
    };

    let review_id = uuid::Uuid::new_v4().to_string();
    let db_lock = db.lock().await;

    // Insert review record
    let _ = db_lock.conn.execute(
        "INSERT INTO review (id, taskId, score, verdict, summary, issues, suggestions, securityNotes, sessionId, costUSD, isApproved, createdAt)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 0, datetime('now'))",
        params![
            review_id,
            task.id,
            score,
            verdict,
            summary,
            issues,
            suggestions,
            security_notes,
            result.session_id,
            result.cost_usd,
        ],
    );

    // Find the coder task that this review is for (the dependency)
    let coder_task_id: Option<String> = db_lock.conn.query_row(
        "SELECT dependsOnTaskId FROM taskDependency WHERE taskId = ?1 LIMIT 1",
        params![task.id],
        |row| row.get(0),
    ).ok();

    if let Some(coder_id) = coder_task_id {
        match verdict {
            "pass" => {
                log::info!("Review passed (score: {:.1}) for coder task {}", score, coder_id);
                // Merge feature branch into dev
                // The git completion handler will handle this
            }
            "needsRevision" => {
                log::info!("Review needs revision (score: {:.1}) for coder task {}", score, coder_id);
                // Requeue the coder task with revision prompt
                let _ = db_lock.conn.execute(
                    "UPDATE agentTask SET status = 'needs_revision', revisionPrompt = ?2, updatedAt = datetime('now') WHERE id = ?1",
                    params![coder_id, format!("Review feedback (score {:.1}):\n{}\n\nIssues: {}\nSuggestions: {}", score, summary, issues.unwrap_or(""), suggestions.unwrap_or(""))],
                );
            }
            _ => {
                log::info!("Review failed (score: {:.1}) for coder task {}", score, coder_id);
                let _ = db_lock.conn.execute(
                    "UPDATE agentTask SET status = 'failed', errorMessage = ?2, updatedAt = datetime('now') WHERE id = ?1",
                    params![coder_id, format!("Review failed with score {:.1}: {}", score, summary)],
                );
            }
        }
    }

    // Emit review event
    if let Some(handle) = app_handle {
        let _ = handle.emit("review-completed", serde_json::json!({
            "reviewId": review_id,
            "taskId": task.id,
            "score": score,
            "verdict": verdict,
        }));
    }
}

/// Creative agents: parse {"assets": [...]} from output, save to DB.
async fn handle_creative_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
) {
    let json = match extract_json(&result.output) {
        Some(j) => j,
        None => {
            // Not JSON — save raw output as a text asset
            save_raw_asset(task, &result.output, db).await;
            return;
        }
    };

    let assets = match json.get("assets").and_then(|a| a.as_array()) {
        Some(a) => a,
        None => {
            save_raw_asset(task, &result.output, db).await;
            return;
        }
    };

    let db_lock = db.lock().await;
    for asset_json in assets {
        let asset_id = uuid::Uuid::new_v4().to_string();
        let name = asset_json.get("name").and_then(|n| n.as_str()).unwrap_or("Untitled");
        let description = asset_json.get("description").and_then(|d| d.as_str()).unwrap_or("");
        let file_path = asset_json.get("filePath").and_then(|f| f.as_str()).unwrap_or("");
        let asset_type = asset_json.get("type").and_then(|t| t.as_str()).unwrap_or("document");
        let mime_type = asset_json.get("mimeType").and_then(|m| m.as_str());
        let source_url = asset_json.get("sourceUrl").and_then(|u| u.as_str());

        let _ = db_lock.conn.execute(
            "INSERT INTO generatedAsset (id, projectId, taskId, agentType, assetType, name, description, filePath, mimeType, sourceUrl, status, version, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'generated', 1, datetime('now'), datetime('now'))",
            params![
                asset_id, task.project_id, task.id, task.agent_type,
                asset_type, name, description, file_path, mime_type, source_url,
            ],
        );

        log::info!("Saved asset '{}' for task {}", name, task.id);
    }
}

/// Save raw text output as a document asset.
async fn save_raw_asset(task: &AgentTask, output: &str, db: &Arc<Mutex<Database>>) {
    if output.is_empty() {
        return;
    }

    let db_lock = db.lock().await;
    let asset_id = uuid::Uuid::new_v4().to_string();
    let _ = db_lock.conn.execute(
        "INSERT INTO generatedAsset (id, projectId, taskId, agentType, assetType, name, description, filePath, status, version, createdAt, updatedAt)
         VALUES (?1, ?2, ?3, ?4, 'document', 'Raw Output', ?5, '', 'generated', 1, datetime('now'), datetime('now'))",
        params![asset_id, task.project_id, task.id, task.agent_type, &output[..output.len().min(500)]],
    );
}

/// Publisher: parse {"publications": [...]} from output.
async fn handle_publisher_completion(
    task: &AgentTask,
    result: &TaskRunResult,
    db: &Arc<Mutex<Database>>,
) {
    let json = match extract_json(&result.output) {
        Some(j) => j,
        None => return,
    };

    let publications = match json.get("publications").and_then(|p| p.as_array()) {
        Some(p) => p,
        None => return,
    };

    let db_lock = db.lock().await;
    for pub_json in publications {
        let pub_id = uuid::Uuid::new_v4().to_string();
        let channel_id = pub_json.get("channelId").and_then(|c| c.as_str()).unwrap_or("");
        let external_id = pub_json.get("externalId").and_then(|e| e.as_str());
        let published_url = pub_json.get("publishedUrl").and_then(|u| u.as_str());
        let status = pub_json.get("status").and_then(|s| s.as_str()).unwrap_or("published");

        let _ = db_lock.conn.execute(
            "INSERT INTO publication (id, assetId, projectId, channelId, status, externalId, publishedUrl, publishedAt, exportFormat, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, datetime('now'), 'markdown', datetime('now'), datetime('now'))",
            params![
                pub_id, task.id, task.project_id, channel_id,
                status, external_id, published_url,
            ],
        );

        log::info!("Recorded publication for channel {} (task {})", channel_id, task.id);
    }
}

/// Git completion pipeline: auto-commit, merge, promote.
async fn handle_git_completion(
    task: &AgentTask,
    db: &Arc<Mutex<Database>>,
    app_handle: Option<&tauri::AppHandle>,
) {
    let dir = {
        let db_lock = db.lock().await;
        let d: Option<String> = db_lock.conn.query_row(
            "SELECT directoryPath FROM project WHERE id = ?1",
            [&task.project_id],
            |row| row.get(0),
        ).ok();
        d.filter(|d| !d.is_empty())
    };

    let dir = match dir {
        Some(d) => d,
        None => return,
    };

    // 1. Auto-commit for non-coder tasks
    if task.agent_type != "coder" {
        match GitBranchManager::auto_commit_if_needed(&dir, &task.id, &task.title, &task.agent_type).await {
            Ok(Some(hash)) => log::info!("Auto-committed {} for task {}", hash, task.id),
            Ok(None) => {}
            Err(e) => log::warn!("Auto-commit failed for task {}: {}", task.id, e),
        }
    }

    // 2. Merge feature branch into dev
    let branch_name = {
        let db_lock = db.lock().await;
        db_lock.conn.query_row(
            "SELECT branchName FROM agentTask WHERE id = ?1",
            [&task.id],
            |row| row.get::<_, Option<String>>(0),
        ).ok().flatten()
    };

    if let Some(branch) = branch_name {
        let protected = ["dev", "staging", "main", "master", "develop"];
        if !protected.contains(&branch.as_str()) {
            match GitBranchManager::merge_feature_to_dev(&dir, &branch).await {
                Ok(()) => log::info!("Merged {} into dev", branch),
                Err(e) => log::warn!("Failed to merge {} into dev: {}", branch, e),
            }
        }
    }

    // 3. Check feature completion → promote
    if let Some(ref feature_id) = task.feature_id {
        let all_passed = {
            let db_lock = db.lock().await;
            let count: i32 = db_lock.conn.query_row(
                "SELECT COUNT(*) FROM agentTask
                 WHERE featureId = ?1 AND archivedAt IS NULL AND status != 'passed' AND status != 'cancelled'",
                params![feature_id],
                |row| row.get(0),
            ).unwrap_or(1);
            count == 0
        };

        if all_passed {
            log::info!("All tasks for feature {} passed — promoting dev to staging", feature_id);
            match GitBranchManager::promote_dev_to_staging(&dir).await {
                Ok(pr_url) => log::info!("Created staging PR: {}", pr_url),
                Err(e) => log::warn!("Failed to promote dev to staging: {}", e),
            }
        }
    }

    // Emit completion event
    if let Some(handle) = app_handle {
        let _ = handle.emit("task-status-changed", serde_json::json!({
            "taskId": task.id,
            "status": "passed",
            "agentType": task.agent_type,
        }));
    }
}
