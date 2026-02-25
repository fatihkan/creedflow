/// Telegram Bot API — sends notifications at key milestones
pub struct TelegramService {
    bot_token: String,
    chat_id: String,
}

impl TelegramService {
    pub fn new(bot_token: String, chat_id: String) -> Self {
        Self { bot_token, chat_id }
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

        reqwest::Client::new()
            .post(&url)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Telegram error: {}", e))?;

        Ok(())
    }
}
