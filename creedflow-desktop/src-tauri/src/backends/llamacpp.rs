use async_trait::async_trait;
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio::sync::mpsc;
use uuid::Uuid;

use super::{build_attachment_prompt, detect, AgentResult, CliBackend, OutputEvent, TaskInput};
use crate::db::models::BackendType;
use crate::services::process_tracker::PROCESS_TRACKER;

pub struct LlamaCppBackend {
    cli_path: Mutex<Option<String>>,
    model_path: Mutex<Option<String>>,
    active: Arc<AtomicUsize>,
    children: Arc<Mutex<HashMap<Uuid, u32>>>,
}

impl LlamaCppBackend {
    pub fn new() -> Self {
        Self {
            cli_path: Mutex::new(detect::find_cli("llama-cli")),
            model_path: Mutex::new(None),
            active: Arc::new(AtomicUsize::new(0)),
            children: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

#[async_trait]
impl CliBackend for LlamaCppBackend {
    fn backend_type(&self) -> BackendType { BackendType::LlamaCpp }

    async fn is_available(&self) -> bool {
        self.cli_path.lock().expect("mutex poisoned").is_some() && self.model_path.lock().expect("mutex poisoned").is_some()
    }

    async fn execute(&self, input: TaskInput) -> Result<(Uuid, mpsc::Receiver<OutputEvent>), String> {
        let path = self.cli_path.lock().expect("mutex poisoned").clone().ok_or("llama-cli not found")?;
        let model = self.model_path.lock().expect("mutex poisoned").clone().ok_or("GGUF model path not set")?;
        let id = Uuid::new_v4();
        let (tx, rx) = mpsc::channel(256);

        // Prepend attachment context to prompt
        let attachment_ctx = build_attachment_prompt(&input.attachments);
        let full_prompt = if attachment_ctx.is_empty() {
            input.prompt
        } else {
            format!("{}\n\n{}", attachment_ctx, input.prompt)
        };

        let mut args = vec![
            "-m".to_string(), model,
            "-p".to_string(), full_prompt,
            "-n".to_string(), "4096".to_string(),
        ];
        if !input.system_prompt.is_empty() {
            args.push("-sys".to_string());
            args.push(input.system_prompt);
        }

        let mut child = Command::new(&path)
            .args(&args)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .stdin(std::process::Stdio::null())
            .spawn()
            .map_err(|e| format!("Failed to spawn llama-cli: {}", e))?;

        let pid = child.id().unwrap_or(0);
        PROCESS_TRACKER.track(pid);
        self.children.lock().expect("mutex poisoned").insert(id, pid);
        self.active.fetch_add(1, Ordering::SeqCst);

        let active = self.active.clone();
        let children = self.children.clone();

        tokio::spawn(async move {
            let mut output = String::new();
            if let Some(mut stdout) = child.stdout.take() {
                let _ = stdout.read_to_string(&mut output).await;
            }
            let _ = tx.send(OutputEvent::Text(output.clone())).await;
            let _ = tx.send(OutputEvent::Result(AgentResult {
                output, cost_usd: None, input_tokens: None, output_tokens: None,
                duration_ms: None, session_id: None, model: Some("llamacpp".to_string()),
            })).await;
            let _ = child.wait().await;
            PROCESS_TRACKER.untrack(pid);
            children.lock().expect("mutex poisoned").remove(&id);
            active.fetch_sub(1, Ordering::SeqCst);
        });

        Ok((id, rx))
    }

    async fn cancel(&self, id: Uuid) {
        if let Some(pid) = self.children.lock().expect("mutex poisoned").remove(&id) {
            crate::services::process_tracker::terminate_process(pid);
            self.active.fetch_sub(1, Ordering::SeqCst);
        }
    }

    async fn cancel_all(&self) {
        let pids: Vec<u32> = self.children.lock().expect("mutex poisoned").drain().map(|(_, p)| p).collect();
        for pid in pids { crate::services::process_tracker::terminate_process(pid); }
        self.active.store(0, Ordering::SeqCst);
    }

    fn active_count(&self) -> usize { self.active.load(Ordering::SeqCst) }
}
