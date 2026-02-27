use async_trait::async_trait;
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio::sync::mpsc;
use uuid::Uuid;

use super::{detect, AgentResult, CliBackend, OutputEvent, TaskInput};
use crate::db::models::BackendType;
use crate::services::process_tracker::PROCESS_TRACKER;

pub struct CodexBackend {
    cli_path: Mutex<Option<String>>,
    active: Arc<AtomicUsize>,
    children: Arc<Mutex<HashMap<Uuid, u32>>>,
}

impl CodexBackend {
    pub fn new() -> Self {
        Self {
            cli_path: Mutex::new(detect::find_cli("codex")),
            active: Arc::new(AtomicUsize::new(0)),
            children: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

#[async_trait]
impl CliBackend for CodexBackend {
    fn backend_type(&self) -> BackendType { BackendType::Codex }

    async fn is_available(&self) -> bool {
        self.cli_path.lock().unwrap().is_some()
    }

    async fn execute(&self, input: TaskInput) -> Result<(Uuid, mpsc::Receiver<OutputEvent>), String> {
        let path = self.cli_path.lock().unwrap().clone().ok_or("Codex CLI not found")?;
        let id = Uuid::new_v4();
        let (tx, rx) = mpsc::channel(256);

        // Temp file to capture clean agent output (bypasses banner on stdout)
        let output_file = std::env::temp_dir().join(format!("codex-output-{}.txt", id));
        let output_file_path = output_file.to_string_lossy().to_string();

        let args = vec![
            "exec".to_string(),
            input.prompt,
            "--full-auto".to_string(),
            "--skip-git-repo-check".to_string(),
            "--output-last-message".to_string(),
            output_file_path.clone(),
        ];

        let mut child = Command::new(&path)
            .args(&args)
            .current_dir(&input.working_directory)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .stdin(std::process::Stdio::null())
            .envs(std::env::vars())
            .spawn()
            .map_err(|e| format!("Failed to spawn Codex: {}", e))?;

        let pid = child.id().unwrap_or(0);
        PROCESS_TRACKER.track(pid);
        self.children.lock().unwrap().insert(id, pid);
        self.active.fetch_add(1, Ordering::SeqCst);

        let active = self.active.clone();
        let children = self.children.clone();
        let output_file_for_task = output_file.clone();

        tokio::spawn(async move {
            // Read stdout for live streaming (includes banner)
            let mut stdout_text = String::new();
            if let Some(mut stdout) = child.stdout.take() {
                let _ = stdout.read_to_string(&mut stdout_text).await;
            }

            let _ = tx.send(OutputEvent::Text(stdout_text.clone())).await;

            let _ = child.wait().await;
            PROCESS_TRACKER.untrack(pid);
            children.lock().unwrap().remove(&id);
            active.fetch_sub(1, Ordering::SeqCst);

            // Prefer clean output from --output-last-message file (no banner)
            let clean_output = tokio::fs::read_to_string(&output_file_for_task)
                .await
                .ok()
                .filter(|s| !s.is_empty());
            let _ = tokio::fs::remove_file(&output_file_for_task).await;

            let final_output = clean_output.unwrap_or(stdout_text);
            let _ = tx.send(OutputEvent::Result(AgentResult {
                output: final_output,
                cost_usd: None,
                input_tokens: None,
                output_tokens: None,
                duration_ms: None,
                session_id: None,
                model: Some("codex".to_string()),
            })).await;
        });

        Ok((id, rx))
    }

    async fn cancel(&self, id: Uuid) {
        if let Some(pid) = self.children.lock().unwrap().remove(&id) {
            crate::services::process_tracker::terminate_process(pid);
            PROCESS_TRACKER.untrack(pid);
            self.active.fetch_sub(1, Ordering::SeqCst);
        }
    }

    async fn cancel_all(&self) {
        let children: Vec<(Uuid, u32)> = self.children.lock().unwrap().drain().collect();
        for (_, pid) in children {
            crate::services::process_tracker::terminate_process(pid);
            PROCESS_TRACKER.untrack(pid);
        }
        self.active.store(0, Ordering::SeqCst);
    }

    fn active_count(&self) -> usize { self.active.load(Ordering::SeqCst) }
}
