use crate::db::Database;
use crate::engine::scheduler::AgentScheduler;
use crate::engine::task_queue::TaskQueue;
use crate::engine::retry::RetryPolicy;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::Emitter;
use tokio::sync::Mutex;
use tokio::time::{interval, Duration};

/// Central orchestration loop — polls TaskQueue every 2 seconds,
/// selects backend via BackendRouter, dispatches tasks to agents.
pub struct Orchestrator {
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
                            // handle completion pipeline
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
