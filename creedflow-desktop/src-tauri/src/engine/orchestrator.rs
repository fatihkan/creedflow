use crate::db::Database;
use crate::db::models::AgentTask;
use crate::engine::scheduler::AgentScheduler;
use crate::engine::task_queue::TaskQueue;
use crate::engine::retry::RetryPolicy;
use crate::services::git_branch_manager::GitBranchManager;
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
    is_running: Arc<AtomicBool>,
    polling_handle: Mutex<Option<tokio::task::JoinHandle<()>>>,
    app_handle: Option<tauri::AppHandle>,
}

impl Orchestrator {
    pub fn new(
        db: Arc<Mutex<Database>>,
        max_concurrency: usize,
        app_handle: Option<tauri::AppHandle>,
    ) -> Self {
        let task_queue = Arc::new(TaskQueue::new(db.clone()));
        let scheduler = Arc::new(AgentScheduler::new(max_concurrency));

        Self {
            db: db.clone(),
            task_queue,
            scheduler,
            retry_policy: RetryPolicy::default(),
            is_running: Arc::new(AtomicBool::new(false)),
            polling_handle: Mutex::new(None),
            app_handle,
        }
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

        let handle = tokio::spawn(async move {
            let mut tick = interval(Duration::from_secs(2));

            while is_running.load(Ordering::SeqCst) {
                tick.tick().await;

                // Try to dequeue a task
                match task_queue.dequeue().await {
                    Ok(Some(task)) => {
                        // Try to acquire a concurrency slot
                        if let Some(_permit) = scheduler.try_acquire() {
                            log::info!("Dispatching task {} ({})", task.id, task.agent_type);

                            // Emit event to frontend
                            if let Some(ref handle) = app_handle {
                                let _ = handle.emit("task-status-changed", serde_json::json!({
                                    "taskId": task.id,
                                    "status": "in_progress",
                                    "agentType": task.agent_type,
                                }));
                            }

                            // TODO: Phase 3 — select backend via BackendRouter,
                            // build agent prompt, execute via MultiBackendRunner,
                            // then call handle_task_completion()
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

    // ─── Task Completion Pipeline ────────────────────────────────────────────

    /// Called after a task finishes successfully. Handles:
    /// 1. Auto-commit changes (non-coder tasks)
    /// 2. Merge feature branch → dev
    /// 3. Check feature completion → promote dev → staging
    pub async fn handle_task_completion(&self, task: &AgentTask) {
        let dir = match self.get_project_dir(&task.project_id).await {
            Some(d) => d,
            None => return,
        };

        // 1. Auto-commit for non-coder tasks (coder has its own commit flow)
        if task.agent_type != "coder" {
            self.auto_commit_changes(task, &dir).await;
        }

        // 2. Universal merge: if task ran on a branch, merge it into dev
        // Re-read task from DB to get fresh branchName
        let branch_name = self.get_task_branch(&task.id).await;
        if let Some(branch) = branch_name {
            self.merge_task_branch_to_dev(&branch, &dir).await;
        }

        // 3. Check if all tasks for this feature passed → promote dev → staging
        if let Some(ref feature_id) = task.feature_id {
            self.check_feature_completion_and_promote(feature_id, &task.project_id, &dir).await;
        }

        // Emit completion event
        if let Some(ref handle) = self.app_handle {
            let _ = handle.emit("task-status-changed", serde_json::json!({
                "taskId": task.id,
                "status": task.status,
                "agentType": task.agent_type,
            }));
        }
    }

    /// Auto-commit any git changes after a task completes (best-effort).
    async fn auto_commit_changes(&self, task: &AgentTask, dir: &str) {
        match GitBranchManager::auto_commit_if_needed(
            dir,
            &task.id,
            &task.title,
            &task.agent_type,
        ).await {
            Ok(Some(hash)) => log::info!("Auto-committed {} for task {}", hash, task.id),
            Ok(None) => {} // No changes to commit
            Err(e) => log::warn!("Auto-commit failed for task {}: {}", task.id, e),
        }
    }

    /// Merge a task's feature branch into dev after completion (best-effort).
    /// This ensures every task's changes end up in dev, even if the GitHub PR
    /// flow failed or was skipped.
    async fn merge_task_branch_to_dev(&self, branch_name: &str, dir: &str) {
        // Skip protected branches
        let protected = ["dev", "staging", "main", "master", "develop"];
        if protected.contains(&branch_name) {
            return;
        }

        match GitBranchManager::merge_feature_to_dev(dir, branch_name).await {
            Ok(()) => log::info!("Merged {} into dev", branch_name),
            Err(e) => log::warn!("Failed to merge {} into dev: {}", branch_name, e),
        }
    }

    /// Check if all tasks for a feature have passed. If so, promote dev → staging.
    async fn check_feature_completion_and_promote(
        &self,
        feature_id: &str,
        _project_id: &str,
        dir: &str,
    ) {
        let all_passed = {
            let db = self.db.lock().await;
            let mut stmt = db.conn.prepare(
                "SELECT COUNT(*) FROM agentTask
                 WHERE featureId = ?1 AND archivedAt IS NULL AND status != 'passed' AND status != 'cancelled'"
            ).ok();
            match stmt.as_mut() {
                Some(s) => {
                    let count: i32 = s.query_row(
                        rusqlite::params![feature_id],
                        |row| row.get(0),
                    ).unwrap_or(1);
                    count == 0
                }
                None => false,
            }
        };

        if all_passed {
            log::info!("All tasks for feature {} passed — promoting dev to staging", feature_id);
            match GitBranchManager::promote_dev_to_staging(dir).await {
                Ok(pr_url) => log::info!("Created staging PR: {}", pr_url),
                Err(e) => log::warn!("Failed to promote dev to staging: {}", e),
            }
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /// Get the project directory path from DB.
    async fn get_project_dir(&self, project_id: &str) -> Option<String> {
        let db = self.db.lock().await;
        let dir: Option<String> = db.conn.query_row(
            "SELECT directoryPath FROM project WHERE id = ?1",
            [project_id],
            |row| row.get(0),
        ).ok();
        dir.filter(|d| !d.is_empty())
    }

    /// Get the branchName for a task from DB (fresh read).
    async fn get_task_branch(&self, task_id: &str) -> Option<String> {
        let db = self.db.lock().await;
        db.conn.query_row(
            "SELECT branchName FROM agentTask WHERE id = ?1",
            [task_id],
            |row| row.get::<_, Option<String>>(0),
        ).ok().flatten()
    }
}
