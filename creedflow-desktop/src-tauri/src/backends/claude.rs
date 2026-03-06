use async_trait::async_trait;
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use tokio::io::AsyncBufReadExt;
use tokio::process::Command;
use tokio::sync::mpsc;
use uuid::Uuid;

use super::{build_attachment_prompt, detect, AgentResult, CliBackend, OutputEvent, TaskInput};
use crate::db::models::BackendType;
use crate::services::process_tracker::PROCESS_TRACKER;

pub struct ClaudeBackend {
    cli_path: Mutex<Option<String>>,
    active: Arc<AtomicUsize>,
    children: Arc<Mutex<HashMap<Uuid, u32>>>,
}

impl ClaudeBackend {
    pub fn new() -> Self {
        Self {
            cli_path: Mutex::new(detect::find_cli("claude")),
            active: Arc::new(AtomicUsize::new(0)),
            children: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    fn get_path(&self) -> Option<String> {
        self.cli_path.lock().expect("cli_path mutex poisoned").clone()
    }
}

#[async_trait]
impl CliBackend for ClaudeBackend {
    fn backend_type(&self) -> BackendType {
        BackendType::Claude
    }

    async fn is_available(&self) -> bool {
        self.get_path().is_some()
    }

    async fn execute(
        &self,
        input: TaskInput,
    ) -> Result<(Uuid, mpsc::Receiver<OutputEvent>), String> {
        let path = self.get_path().ok_or("Claude CLI not found")?;
        let id = Uuid::new_v4();
        let (tx, rx) = mpsc::channel(256);

        // Prepend attachment context to prompt
        let attachment_ctx = build_attachment_prompt(&input.attachments);
        let full_prompt = if attachment_ctx.is_empty() {
            input.prompt.clone()
        } else {
            format!("{}\n\n{}", attachment_ctx, input.prompt)
        };

        let mut args = vec![
            "-p".to_string(),
            full_prompt,
            "--output-format".to_string(),
            "stream-json".to_string(),
        ];

        if !input.system_prompt.is_empty() {
            args.push("--system-prompt".to_string());
            args.push(input.system_prompt.clone());
        }

        if let Some(ref tools) = input.allowed_tools {
            for tool in tools {
                args.push("--allowedTools".to_string());
                args.push(tool.clone());
            }
        }

        if let Some(budget) = input.max_budget_usd {
            args.push("--max-turns-budget".to_string());
            args.push(format!("{:.2}", budget));
        }

        if let Some(ref mcp_config) = input.mcp_config_path {
            args.push("--mcp-config".to_string());
            args.push(mcp_config.clone());
        }

        let mut child = Command::new(&path)
            .args(&args)
            .current_dir(&input.working_directory)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .stdin(std::process::Stdio::null())
            .envs(std::env::vars())
            .spawn()
            .map_err(|e| format!("Failed to spawn Claude: {}", e))?;

        let pid = child.id().unwrap_or(0);
        PROCESS_TRACKER.track(pid);
        self.children.lock().expect("children mutex poisoned").insert(id, pid);
        self.active.fetch_add(1, Ordering::SeqCst);

        let active = self.active.clone();
        let children = self.children.clone();

        tokio::spawn(async move {
            let stdout = child.stdout.take();
            if let Some(stdout) = stdout {
                let reader = tokio::io::BufReader::new(stdout);
                let mut lines = reader.lines();
                let mut full_output = String::new();

                while let Ok(Some(line)) = lines.next_line().await {
                    if line.trim().is_empty() {
                        continue;
                    }
                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&line) {
                        match json.get("type").and_then(|t| t.as_str()) {
                            Some("assistant") => {
                                if let Some(msg) = json.get("message")
                                    .and_then(|m| m.get("content"))
                                    .and_then(|c| c.as_array())
                                {
                                    for block in msg {
                                        if let Some(text) = block.get("text").and_then(|t| t.as_str()) {
                                            full_output.push_str(text);
                                            let _ = tx.send(OutputEvent::Text(text.to_string())).await;
                                        }
                                    }
                                }
                            }
                            Some("content_block_delta") => {
                                if let Some(text) = json.get("delta")
                                    .and_then(|d| d.get("text"))
                                    .and_then(|t| t.as_str())
                                {
                                    full_output.push_str(text);
                                    let _ = tx.send(OutputEvent::Text(text.to_string())).await;
                                }
                            }
                            Some("result") => {
                                let cost = json.get("cost_usd").and_then(|c| c.as_f64());
                                let input_tokens = json.get("input_tokens").and_then(|t| t.as_i64());
                                let output_tokens = json.get("output_tokens").and_then(|t| t.as_i64());
                                let session_id = json.get("session_id").and_then(|s| s.as_str()).map(|s| s.to_string());
                                let model = json.get("model").and_then(|m| m.as_str()).map(|m| m.to_string());
                                let duration_ms = json.get("duration_ms").and_then(|d| d.as_i64());
                                if let Some(result_text) = json.get("result").and_then(|r| r.as_str()) {
                                    full_output = result_text.to_string();
                                }
                                let _ = tx.send(OutputEvent::Result(AgentResult {
                                    output: full_output.clone(),
                                    cost_usd: cost,
                                    input_tokens,
                                    output_tokens,
                                    duration_ms,
                                    session_id,
                                    model,
                                })).await;
                            }
                            Some("system") => {
                                let session_id = json.get("session_id")
                                    .and_then(|s| s.as_str())
                                    .unwrap_or("")
                                    .to_string();
                                let model = json.get("model")
                                    .and_then(|m| m.as_str())
                                    .unwrap_or("")
                                    .to_string();
                                let _ = tx.send(OutputEvent::System { session_id, model }).await;
                            }
                            _ => {
                                let _ = tx.send(OutputEvent::Text(line)).await;
                            }
                        }
                    } else {
                        full_output.push_str(&line);
                        full_output.push('\n');
                        let _ = tx.send(OutputEvent::Text(line)).await;
                    }
                }
            }

            let _ = child.wait().await;
            PROCESS_TRACKER.untrack(pid);
            children.lock().expect("children mutex poisoned").remove(&id);
            active.fetch_sub(1, Ordering::SeqCst);
        });

        Ok((id, rx))
    }

    async fn cancel(&self, id: Uuid) {
        if let Some(pid) = self.children.lock().expect("children mutex poisoned").remove(&id) {
            crate::services::process_tracker::terminate_process(pid);
            PROCESS_TRACKER.untrack(pid);
            self.active.fetch_sub(1, Ordering::SeqCst);
        }
    }

    async fn cancel_all(&self) {
        let children: Vec<(Uuid, u32)> = self.children.lock().expect("children mutex poisoned").drain().collect();
        for (_, pid) in children {
            crate::services::process_tracker::terminate_process(pid);
            PROCESS_TRACKER.untrack(pid);
        }
        self.active.store(0, Ordering::SeqCst);
    }

    fn active_count(&self) -> usize {
        self.active.load(Ordering::SeqCst)
    }
}
