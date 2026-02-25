/// GitHub API integration via reqwest
pub struct GitHubService {
    token: Option<String>,
}

impl GitHubService {
    pub fn new(token: Option<String>) -> Self {
        Self { token }
    }

    pub async fn create_pr(
        &self,
        owner: &str,
        repo: &str,
        title: &str,
        body: &str,
        head: &str,
        base: &str,
    ) -> Result<serde_json::Value, String> {
        let token = self.token.as_ref().ok_or("GitHub token not set")?;
        let url = format!("https://api.github.com/repos/{}/{}/pulls", owner, repo);
        let body_json = serde_json::json!({
            "title": title,
            "body": body,
            "head": head,
            "base": base,
        });

        let resp = reqwest::Client::new()
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", "CreedFlow")
            .json(&body_json)
            .send()
            .await
            .map_err(|e| format!("GitHub API error: {}", e))?;

        resp.json::<serde_json::Value>()
            .await
            .map_err(|e| format!("JSON parse error: {}", e))
    }
}
