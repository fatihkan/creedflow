use super::PublishResult;

/// Medium API publisher.
pub struct MediumPublisher;

impl MediumPublisher {
    /// Publish an article to Medium.
    pub async fn publish(
        token: &str,
        title: &str,
        content: &str,
        tags: &[String],
    ) -> Result<PublishResult, String> {
        let client = reqwest::Client::new();

        // 1. Get authenticated user ID
        let user_resp = client
            .get("https://api.medium.com/v1/me")
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| format!("Medium API error: {}", e))?;

        let user_json: serde_json::Value = user_resp
            .json()
            .await
            .map_err(|e| format!("Failed to parse Medium response: {}", e))?;

        let user_id = user_json
            .get("data")
            .and_then(|d| d.get("id"))
            .and_then(|i| i.as_str())
            .ok_or("Failed to get Medium user ID")?;

        // 2. Create post
        let body = serde_json::json!({
            "title": title,
            "contentFormat": "markdown",
            "content": content,
            "tags": tags.iter().take(5).collect::<Vec<_>>(), // Medium allows max 5 tags
            "publishStatus": "draft",
        });

        let post_resp = client
            .post(format!(
                "https://api.medium.com/v1/users/{}/posts",
                user_id
            ))
            .bearer_auth(token)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Medium publish error: {}", e))?;

        let post_json: serde_json::Value = post_resp
            .json()
            .await
            .map_err(|e| format!("Failed to parse Medium post response: {}", e))?;

        let post_id = post_json
            .get("data")
            .and_then(|d| d.get("id"))
            .and_then(|i| i.as_str())
            .map(|s| s.to_string());

        let post_url = post_json
            .get("data")
            .and_then(|d| d.get("url"))
            .and_then(|u| u.as_str())
            .map(|s| s.to_string());

        Ok(PublishResult {
            external_id: post_id,
            published_url: post_url,
        })
    }
}
