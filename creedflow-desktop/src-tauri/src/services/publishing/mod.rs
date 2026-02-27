pub mod medium;
pub mod wordpress;
pub mod social;

use crate::db::Database;
use rusqlite::params;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Content publishing coordinator — routes content to configured channels.
pub struct ContentPublishingService {
    db: Arc<Mutex<Database>>,
}

impl ContentPublishingService {
    pub fn new(db: Arc<Mutex<Database>>) -> Self {
        Self { db }
    }

    /// Publish content to a specific channel.
    pub async fn publish(
        &self,
        publication_id: &str,
        channel_type: &str,
        title: &str,
        content: &str,
        tags: &[String],
        credentials: &serde_json::Value,
    ) -> Result<PublishResult, String> {
        let result = match channel_type {
            "medium" => {
                let token = credentials
                    .get("token")
                    .and_then(|t| t.as_str())
                    .ok_or("Missing Medium integration token")?;
                medium::MediumPublisher::publish(token, title, content, tags).await
            }
            "wordpress" => {
                let url = credentials
                    .get("url")
                    .and_then(|u| u.as_str())
                    .ok_or("Missing WordPress URL")?;
                let username = credentials
                    .get("username")
                    .and_then(|u| u.as_str())
                    .ok_or("Missing WordPress username")?;
                let password = credentials
                    .get("password")
                    .and_then(|p| p.as_str())
                    .ok_or("Missing WordPress password")?;
                wordpress::WordPressPublisher::publish(url, username, password, title, content, tags)
                    .await
            }
            "twitter" => {
                social::SocialPublisher::publish_twitter(credentials, title, content).await
            }
            "linkedin" => {
                social::SocialPublisher::publish_linkedin(credentials, title, content).await
            }
            _ => Err(format!("Unsupported channel type: {}", channel_type)),
        };

        // Update publication status in DB
        match &result {
            Ok(r) => {
                let db_lock = self.db.lock().await;
                let _ = db_lock.conn.execute(
                    "UPDATE publication SET status = 'published', externalId = ?2, publishedUrl = ?3, publishedAt = datetime('now'), updatedAt = datetime('now') WHERE id = ?1",
                    params![publication_id, r.external_id, r.published_url],
                );
            }
            Err(e) => {
                let db_lock = self.db.lock().await;
                let _ = db_lock.conn.execute(
                    "UPDATE publication SET status = 'failed', errorMessage = ?2, updatedAt = datetime('now') WHERE id = ?1",
                    params![publication_id, e],
                );
            }
        }

        result
    }
}

/// Result of a publish operation.
#[derive(Debug, Clone)]
pub struct PublishResult {
    pub external_id: Option<String>,
    pub published_url: Option<String>,
}
