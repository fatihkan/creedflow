use crate::db::Database;
use crate::db::models::{AppNotification, NotificationCategory, NotificationSeverity};
use chrono::Utc;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

/// Central notification service — persists to DB, buffers toasts in memory.
pub struct NotificationService {
    db: Arc<Mutex<Database>>,
    toast_buffer: Arc<Mutex<Vec<AppNotification>>>,
}

impl NotificationService {
    pub fn new(db: Arc<Mutex<Database>>) -> Self {
        Self {
            db,
            toast_buffer: Arc::new(Mutex::new(Vec::new())),
        }
    }

    /// Emit a new notification — persists to DB and adds to toast buffer.
    pub async fn emit(
        &self,
        category: NotificationCategory,
        severity: NotificationSeverity,
        title: &str,
        message: &str,
    ) {
        let notif = AppNotification {
            id: Uuid::new_v4().to_string(),
            category: category.as_str().to_string(),
            severity: severity.as_str().to_string(),
            title: title.to_string(),
            message: message.to_string(),
            metadata: None,
            is_read: false,
            is_dismissed: false,
            created_at: Utc::now().format("%Y-%m-%d %H:%M:%S").to_string(),
        };

        // Persist to DB
        {
            let db_lock = self.db.lock().await;
            let _ = AppNotification::insert(&db_lock.conn, &notif);
        }

        // Add to toast buffer (max 5)
        {
            let mut buffer = self.toast_buffer.lock().await;
            buffer.push(notif);
            if buffer.len() > 5 {
                buffer.remove(0);
            }
        }
    }

    /// Drain pending toasts — returns them and clears the buffer.
    pub async fn drain_toasts(&self) -> Vec<AppNotification> {
        let mut buffer = self.toast_buffer.lock().await;
        std::mem::take(&mut *buffer)
    }

    /// Prune notifications older than `days`.
    pub async fn prune_old(&self, days: i32) {
        let db_lock = self.db.lock().await;
        let _ = AppNotification::prune_old(&db_lock.conn, days);
    }
}
