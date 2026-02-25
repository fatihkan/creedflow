use crate::db::Database;
use crate::db::models::AgentTask;
use rusqlite::params;
use std::sync::Arc;
use tokio::sync::Mutex;

/// SQLite-backed priority queue with dependency-aware dequeue.
/// Mirrors the Swift TaskQueue exactly.
pub struct TaskQueue {
    db: Arc<Mutex<Database>>,
}

impl TaskQueue {
    pub fn new(db: Arc<Mutex<Database>>) -> Self {
        Self { db }
    }

    /// Atomically dequeue the next ready task.
    /// Ready = queued AND all dependencies have status 'passed'.
    pub async fn dequeue(&self) -> Result<Option<AgentTask>, String> {
        let db = self.db.lock().await;
        let tx = db.conn.unchecked_transaction().map_err(|e| e.to_string())?;

        let result: Option<AgentTask> = tx.query_row(
            "SELECT * FROM agentTask t
             WHERE t.status = 'queued'
               AND NOT EXISTS (
                 SELECT 1 FROM taskDependency td
                 JOIN agentTask dep ON dep.id = td.dependsOnTaskId
                 WHERE td.taskId = t.id AND dep.status != 'passed'
               )
             ORDER BY t.priority DESC, t.createdAt ASC
             LIMIT 1",
            [],
            |row| AgentTask::from_row(row),
        ).optional().map_err(|e| e.to_string())?;

        if let Some(ref task) = result {
            tx.execute(
                "UPDATE agentTask SET status = 'in_progress', startedAt = datetime('now'), updatedAt = datetime('now') WHERE id = ?1",
                params![task.id],
            ).map_err(|e| e.to_string())?;
        }

        tx.commit().map_err(|e| e.to_string())?;
        Ok(result)
    }

    /// Requeue a task for retry (increments retryCount).
    pub async fn requeue(&self, task_id: &str) -> Result<(), String> {
        let db = self.db.lock().await;
        db.conn.execute(
            "UPDATE agentTask SET status = 'queued', retryCount = retryCount + 1, startedAt = NULL, updatedAt = datetime('now') WHERE id = ?1",
            params![task_id],
        ).map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Defer a task without incrementing retryCount (no slot available, not a failure).
    pub async fn defer_task(&self, task_id: &str) -> Result<(), String> {
        let db = self.db.lock().await;
        db.conn.execute(
            "UPDATE agentTask SET status = 'queued', startedAt = NULL, updatedAt = datetime('now') WHERE id = ?1",
            params![task_id],
        ).map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Mark a task as failed with an error message.
    pub async fn fail(&self, task_id: &str, error: &str) -> Result<(), String> {
        let db = self.db.lock().await;
        db.conn.execute(
            "UPDATE agentTask SET status = 'failed', errorMessage = ?2, completedAt = datetime('now'), updatedAt = datetime('now') WHERE id = ?1",
            params![task_id, error],
        ).map_err(|e| e.to_string())?;
        Ok(())
    }

    /// On startup: recover tasks stuck in in_progress (app crashed).
    pub async fn recover_orphaned_tasks(&self) -> Result<i32, String> {
        let db = self.db.lock().await;
        let mut stmt = db.conn.prepare(
            "SELECT * FROM agentTask WHERE status = 'in_progress'"
        ).map_err(|e| e.to_string())?;

        let orphans: Vec<AgentTask> = stmt.query_map([], |row| AgentTask::from_row(row))
            .map_err(|e| e.to_string())?
            .filter_map(|r| r.ok())
            .collect();

        let count = orphans.len() as i32;
        for task in &orphans {
            if task.retry_count < task.max_retries {
                db.conn.execute(
                    "UPDATE agentTask SET status = 'queued', retryCount = retryCount + 1, startedAt = NULL, updatedAt = datetime('now') WHERE id = ?1",
                    params![task.id],
                ).map_err(|e| e.to_string())?;
            } else {
                db.conn.execute(
                    "UPDATE agentTask SET status = 'failed', errorMessage = 'Orphaned after app restart', completedAt = datetime('now'), updatedAt = datetime('now') WHERE id = ?1",
                    params![task.id],
                ).map_err(|e| e.to_string())?;
            }
        }

        if count > 0 {
            log::info!("Recovered {} orphaned tasks", count);
        }
        Ok(count)
    }
}

/// Extension trait for rusqlite to support optional query results.
trait OptionalExt<T> {
    fn optional(self) -> Result<Option<T>, rusqlite::Error>;
}

impl<T> OptionalExt<T> for Result<T, rusqlite::Error> {
    fn optional(self) -> Result<Option<T>, rusqlite::Error> {
        match self {
            Ok(v) => Ok(Some(v)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }
}
