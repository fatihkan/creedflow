use super::PublishResult;
use crate::services::content_exporter::ContentExporter;

/// WordPress REST API publisher.
pub struct WordPressPublisher;

impl WordPressPublisher {
    /// Publish a post to WordPress via REST API.
    pub async fn publish(
        site_url: &str,
        username: &str,
        password: &str,
        title: &str,
        markdown_content: &str,
        tags: &[String],
    ) -> Result<PublishResult, String> {
        let client = reqwest::Client::new();
        let html_content = ContentExporter::markdown_to_html(markdown_content);

        let url = format!("{}/wp-json/wp/v2/posts", site_url.trim_end_matches('/'));

        let body = serde_json::json!({
            "title": title,
            "content": html_content,
            "status": "draft",
            "tags": tags,
        });

        let resp = client
            .post(&url)
            .basic_auth(username, Some(password))
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("WordPress API error: {}", e))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("WordPress returned {}: {}", status, body));
        }

        let post_json: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| format!("Failed to parse WordPress response: {}", e))?;

        let post_id = post_json
            .get("id")
            .and_then(|i| i.as_i64())
            .map(|i| i.to_string());

        let post_url = post_json
            .get("link")
            .and_then(|l| l.as_str())
            .map(|s| s.to_string());

        Ok(PublishResult {
            external_id: post_id,
            published_url: post_url,
        })
    }
}
