use async_trait::async_trait;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use tokio::sync::mpsc;
use uuid::Uuid;

use super::{build_attachment_prompt, AgentResult, CliBackend, OutputEvent, TaskInput};
use crate::db::models::BackendType;

pub struct LMStudioBackend {
    base_url: String,
    active: Arc<AtomicUsize>,
}

impl LMStudioBackend {
    pub fn new() -> Self {
        Self {
            base_url: "http://localhost:1234".to_string(),
            active: Arc::new(AtomicUsize::new(0)),
        }
    }
}

#[async_trait]
impl CliBackend for LMStudioBackend {
    fn backend_type(&self) -> BackendType { BackendType::LmStudio }

    async fn is_available(&self) -> bool {
        let url = format!("{}/v1/models", self.base_url);
        reqwest::get(&url).await.map(|r| r.status().is_success()).unwrap_or(false)
    }

    async fn execute(&self, input: TaskInput) -> Result<(Uuid, mpsc::Receiver<OutputEvent>), String> {
        let id = Uuid::new_v4();
        let (tx, rx) = mpsc::channel(256);
        let url = format!("{}/v1/chat/completions", self.base_url);

        self.active.fetch_add(1, Ordering::SeqCst);
        let active = self.active.clone();

        tokio::spawn(async move {
            // Prepend attachment context to prompt
            let attachment_ctx = build_attachment_prompt(&input.attachments);
            let full_prompt = if attachment_ctx.is_empty() {
                input.prompt.clone()
            } else {
                format!("{}\n\n{}", attachment_ctx, input.prompt)
            };

            let body = serde_json::json!({
                "messages": [
                    { "role": "system", "content": input.system_prompt },
                    { "role": "user", "content": full_prompt },
                ],
                "temperature": 0.7,
                "max_tokens": 4096,
                "stream": false,
            });

            match reqwest::Client::new().post(&url).json(&body).send().await {
                Ok(resp) => {
                    if let Ok(json) = resp.json::<serde_json::Value>().await {
                        let output = json["choices"][0]["message"]["content"]
                            .as_str()
                            .unwrap_or("")
                            .to_string();
                        let _ = tx.send(OutputEvent::Text(output.clone())).await;
                        let _ = tx.send(OutputEvent::Result(AgentResult {
                            output, cost_usd: None, input_tokens: None,
                            output_tokens: None, duration_ms: None,
                            session_id: None, model: Some("lmstudio".to_string()),
                        })).await;
                    }
                }
                Err(e) => {
                    let _ = tx.send(OutputEvent::Error(format!("LM Studio error: {}", e))).await;
                }
            }
            active.fetch_sub(1, Ordering::SeqCst);
        });

        Ok((id, rx))
    }

    async fn cancel(&self, _id: Uuid) {
        self.active.fetch_sub(1, Ordering::SeqCst);
    }

    async fn cancel_all(&self) {
        self.active.store(0, Ordering::SeqCst);
    }

    fn active_count(&self) -> usize { self.active.load(Ordering::SeqCst) }
}
