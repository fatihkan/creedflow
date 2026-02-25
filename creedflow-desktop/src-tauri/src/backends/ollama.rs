use async_trait::async_trait;
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio::sync::mpsc;
use uuid::Uuid;

use super::{detect, AgentResult, CliBackend, OutputEvent, TaskInput};
use crate::db::models::BackendType;
use crate::services::process_tracker::PROCESS_TRACKER;

pub struct OllamaBackend {
    cli_path: Mutex<Option<String>>,
    model: Mutex<String>,
    active: AtomicUsize,
    children: Mutex<HashMap<Uuid, u32>>,
}

impl OllamaBackend {
    pub fn new() -> Self {
        Self {
            cli_path: Mutex::new(detect::find_cli("ollama")),
            model: Mutex::new("llama3.2".to_string()),
            active: AtomicUsize::new(0),
            children: Mutex::new(HashMap::new()),
        }
    }
}

#[async_trait]
impl CliBackend for OllamaBackend {
    fn backend_type(&self) -> BackendType { BackendType::Ollama }

    async fn is_available(&self) -> bool {
        self.cli_path.lock().unwrap().is_some()
    }

    async fn execute(&self, input: TaskInput) -> Result<(Uuid, mpsc::Receiver<OutputEvent>), String> {
        let path = self.cli_path.lock().unwrap().clone().ok_or("Ollama CLI not found")?;
        let model = self.model.lock().unwrap().clone();
        let id = Uuid::new_v4();
        let (tx, rx) = mpsc::channel(256);

        // ollama run <model> "<prompt>"
        let args = vec!["run".to_string(), model, input.prompt];

        let mut child = Command::new(&path)
            .args(&args)
            .current_dir(&input.working_directory)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .stdin(std::process::Stdio::null())
            .envs(std::env::vars())
            .spawn()
            .map_err(|e| format!("Failed to spawn Ollama: {}", e))?;

        let pid = child.id().unwrap_or(0);
        PROCESS_TRACKER.track(pid);
        self.children.lock().unwrap().insert(id, pid);
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
                duration_ms: None, session_id: None, model: Some("ollama".to_string()),
            })).await;
            let _ = child.wait().await;
            PROCESS_TRACKER.untrack(pid);
            children.lock().unwrap().remove(&id);
            active.fetch_sub(1, Ordering::SeqCst);
        });

        Ok((id, rx))
    }

    async fn cancel(&self, id: Uuid) {
        if let Some(pid) = self.children.lock().unwrap().remove(&id) {
            crate::services::process_tracker::terminate_process(pid);
            self.active.fetch_sub(1, Ordering::SeqCst);
        }
    }

    async fn cancel_all(&self) {
        let pids: Vec<u32> = self.children.lock().unwrap().drain().map(|(_, p)| p).collect();
        for pid in pids { crate::services::process_tracker::terminate_process(pid); }
        self.active.store(0, Ordering::SeqCst);
    }

    fn active_count(&self) -> usize { self.active.load(Ordering::SeqCst) }
}
