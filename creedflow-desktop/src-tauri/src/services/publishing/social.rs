use super::PublishResult;

/// Social media publisher — Twitter and LinkedIn sharing.
pub struct SocialPublisher;

impl SocialPublisher {
    /// Post to Twitter/X (OAuth 2.0).
    pub async fn publish_twitter(
        credentials: &serde_json::Value,
        _title: &str,
        content: &str,
    ) -> Result<PublishResult, String> {
        let bearer_token = credentials
            .get("bearerToken")
            .and_then(|t| t.as_str())
            .ok_or("Missing Twitter bearer token")?;

        // Truncate to 280 characters for Twitter
        let tweet_text = if content.len() > 280 {
            format!("{}...", &content[..277])
        } else {
            content.to_string()
        };

        let client = reqwest::Client::new();
        let body = serde_json::json!({
            "text": tweet_text,
        });

        let resp = client
            .post("https://api.twitter.com/2/tweets")
            .bearer_auth(bearer_token)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Twitter API error: {}", e))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("Twitter returned {}: {}", status, body));
        }

        let resp_json: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| format!("Failed to parse Twitter response: {}", e))?;

        let tweet_id = resp_json
            .get("data")
            .and_then(|d| d.get("id"))
            .and_then(|i| i.as_str())
            .map(|s| s.to_string());

        let tweet_url = tweet_id
            .as_ref()
            .map(|id| format!("https://twitter.com/i/status/{}", id));

        Ok(PublishResult {
            external_id: tweet_id,
            published_url: tweet_url,
        })
    }

    /// Post to LinkedIn (OAuth 2.0).
    pub async fn publish_linkedin(
        credentials: &serde_json::Value,
        _title: &str,
        content: &str,
    ) -> Result<PublishResult, String> {
        let access_token = credentials
            .get("accessToken")
            .and_then(|t| t.as_str())
            .ok_or("Missing LinkedIn access token")?;

        let person_urn = credentials
            .get("personUrn")
            .and_then(|u| u.as_str())
            .ok_or("Missing LinkedIn person URN")?;

        // Truncate for LinkedIn (3000 char limit for text posts)
        let post_text = if content.len() > 3000 {
            format!("{}...", &content[..2997])
        } else {
            content.to_string()
        };

        let client = reqwest::Client::new();
        let body = serde_json::json!({
            "author": person_urn,
            "lifecycleState": "PUBLISHED",
            "specificContent": {
                "com.linkedin.ugc.ShareContent": {
                    "shareCommentary": {
                        "text": post_text,
                    },
                    "shareMediaCategory": "NONE",
                }
            },
            "visibility": {
                "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC",
            }
        });

        let resp = client
            .post("https://api.linkedin.com/v2/ugcPosts")
            .bearer_auth(access_token)
            .header("X-Restli-Protocol-Version", "2.0.0")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("LinkedIn API error: {}", e))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("LinkedIn returned {}: {}", status, body));
        }

        let post_id = resp
            .headers()
            .get("x-restli-id")
            .and_then(|h| h.to_str().ok())
            .map(|s| s.to_string());

        Ok(PublishResult {
            external_id: post_id,
            published_url: None, // LinkedIn doesn't return URL in create response
        })
    }
}
