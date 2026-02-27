/// Telegram Bot API — sends notifications at key milestones.
pub struct TelegramService {
    bot_token: String,
    chat_id: String,
    client: reqwest::Client,
}

impl TelegramService {
    pub fn new(bot_token: String, chat_id: String) -> Self {
        Self {
            bot_token,
            chat_id,
            client: reqwest::Client::new(),
        }
    }

    pub async fn send_message(&self, text: &str) -> Result<(), String> {
        let url = format!(
            "https://api.telegram.org/bot{}/sendMessage",
            self.bot_token
        );
        let body = serde_json::json!({
            "chat_id": self.chat_id,
            "text": text,
            "parse_mode": "Markdown",
        });

        self.client
            .post(&url)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Telegram error: {}", e))?;

        Ok(())
    }

    /// Notify on task completion.
    pub async fn notify_task_completion(
        &self,
        task_title: &str,
        agent_type: &str,
        backend: &str,
        cost_usd: Option<f64>,
        duration_ms: Option<i64>,
    ) {
        let cost_str = cost_usd
            .map(|c| format!("${:.4}", c))
            .unwrap_or_else(|| "-".to_string());
        let duration_str = duration_ms
            .map(|d| format!("{:.1}s", d as f64 / 1000.0))
            .unwrap_or_else(|| "-".to_string());

        let msg = format!(
            "✅ *Task Completed*\n\n\
             *Title:* {}\n\
             *Agent:* {}\n\
             *Backend:* {}\n\
             *Cost:* {}\n\
             *Duration:* {}",
            escape_markdown(task_title),
            agent_type,
            backend,
            cost_str,
            duration_str,
        );
        let _ = self.send_message(&msg).await;
    }

    /// Notify on task failure.
    pub async fn notify_task_failure(
        &self,
        task_title: &str,
        agent_type: &str,
        error: &str,
        retry_count: i32,
        max_retries: i32,
    ) {
        let msg = format!(
            "❌ *Task Failed*\n\n\
             *Title:* {}\n\
             *Agent:* {}\n\
             *Error:* {}\n\
             *Retries:* {}/{}",
            escape_markdown(task_title),
            agent_type,
            escape_markdown(error),
            retry_count,
            max_retries,
        );
        let _ = self.send_message(&msg).await;
    }

    /// Notify on deployment.
    pub async fn notify_deploy(
        &self,
        project_name: &str,
        environment: &str,
        status: &str,
        version: &str,
    ) {
        let emoji = match status {
            "success" => "🚀",
            "failed" => "💥",
            _ => "📦",
        };
        let msg = format!(
            "{} *Deployment {}*\n\n\
             *Project:* {}\n\
             *Environment:* {}\n\
             *Version:* {}",
            emoji,
            status,
            escape_markdown(project_name),
            environment,
            escape_markdown(version),
        );
        let _ = self.send_message(&msg).await;
    }

    /// Notify on feature completion (all tasks passed).
    pub async fn notify_feature_completion(
        &self,
        feature_name: &str,
        project_name: &str,
    ) {
        let msg = format!(
            "🎉 *Feature Complete*\n\n\
             *Feature:* {}\n\
             *Project:* {}\n\n\
             All tasks passed — promoting to staging.",
            escape_markdown(feature_name),
            escape_markdown(project_name),
        );
        let _ = self.send_message(&msg).await;
    }

    /// Notify on project analysis completion.
    pub async fn notify_analysis_complete(
        &self,
        project_name: &str,
        feature_count: usize,
        task_count: usize,
    ) {
        let msg = format!(
            "🔍 *Analysis Complete*\n\n\
             *Project:* {}\n\
             *Features:* {}\n\
             *Tasks:* {}\n\n\
             Tasks queued for execution.",
            escape_markdown(project_name),
            feature_count,
            task_count,
        );
        let _ = self.send_message(&msg).await;
    }
}

/// Escape Telegram Markdown special characters.
fn escape_markdown(text: &str) -> String {
    text.replace('_', "\\_")
        .replace('*', "\\*")
        .replace('[', "\\[")
        .replace('`', "\\`")
}
