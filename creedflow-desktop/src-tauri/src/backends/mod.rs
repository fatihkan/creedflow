pub mod detect;
pub mod claude;
pub mod codex;
pub mod gemini;
pub mod ollama;
pub mod lmstudio;
pub mod llamacpp;
pub mod mlx;
pub mod opencode;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::sync::atomic::AtomicUsize;
use tokio::sync::mpsc;
use uuid::Uuid;

use crate::db::models::BackendType;

// ─── CLI Backend Trait ───────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskInput {
    pub prompt: String,
    pub system_prompt: String,
    pub working_directory: String,
    pub allowed_tools: Option<Vec<String>>,
    pub max_budget_usd: Option<f64>,
    pub timeout_seconds: i32,
    pub mcp_config_path: Option<String>,
    pub json_schema: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum OutputEvent {
    Text(String),
    ToolUse(String),
    System { session_id: String, model: String },
    Result(AgentResult),
    Error(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentResult {
    pub output: String,
    pub cost_usd: Option<f64>,
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub duration_ms: Option<i64>,
    pub session_id: Option<String>,
    pub model: Option<String>,
}

#[async_trait]
pub trait CliBackend: Send + Sync {
    fn backend_type(&self) -> BackendType;
    async fn is_available(&self) -> bool;
    async fn execute(&self, input: TaskInput) -> Result<(Uuid, mpsc::Receiver<OutputEvent>), String>;
    async fn cancel(&self, id: Uuid);
    async fn cancel_all(&self);
    fn active_count(&self) -> usize;
}

// ─── Backend Preferences ─────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BackendPreferences {
    /// Only Claude (agents needing MCP/tools: Coder, Reviewer, Tester)
    ClaudeOnly,
    /// Prefers Claude, falls back to Codex/Gemini/local
    ClaudePreferred,
    /// Round-robin all backends (Analyzer)
    AnyBackend,
    /// Codex/Gemini preferred (DevOps, Monitor)
    Default,
}

impl BackendPreferences {
    pub fn requires_claude_features(&self) -> bool {
        matches!(self, Self::ClaudeOnly)
    }

    pub fn preferred_backends(&self) -> Vec<BackendType> {
        match self {
            Self::ClaudeOnly => vec![BackendType::Claude],
            Self::ClaudePreferred => vec![
                BackendType::Claude, BackendType::Codex, BackendType::Gemini,
            ],
            Self::AnyBackend => vec![
                BackendType::Claude, BackendType::Codex, BackendType::Gemini,
            ],
            Self::Default => vec![
                BackendType::Codex, BackendType::Gemini, BackendType::Claude,
            ],
        }
    }
}

// ─── Backend Router ──────────────────────────────────────────────────────────

pub struct BackendRouter {
    backends: Vec<Box<dyn CliBackend>>,
    round_robin: AtomicUsize,
    enabled: std::sync::Mutex<std::collections::HashSet<String>>,
}

impl BackendRouter {
    pub fn new(backends: Vec<Box<dyn CliBackend>>) -> Self {
        let mut enabled = std::collections::HashSet::new();
        // Cloud backends enabled by default
        enabled.insert("claude".to_string());
        enabled.insert("codex".to_string());
        enabled.insert("gemini".to_string());

        Self {
            backends,
            round_robin: AtomicUsize::new(0),
            enabled: std::sync::Mutex::new(enabled),
        }
    }

    pub fn set_enabled(&self, backend_type: &str, enabled: bool) {
        let mut set = self.enabled.lock().unwrap();
        if enabled {
            set.insert(backend_type.to_string());
        } else {
            set.remove(backend_type);
        }
    }

    pub async fn select_backend(
        &self,
        preferences: &BackendPreferences,
    ) -> Option<&dyn CliBackend> {
        let enabled = self.enabled.lock().unwrap().clone();

        // If requires Claude features, try Claude first
        if preferences.requires_claude_features() {
            if let Some(b) = self.find_usable("claude", &enabled).await {
                return Some(b);
            }
            log::warn!("Claude required but not available");
            return None;
        }

        // Try preferred backends in order
        for bt in preferences.preferred_backends() {
            if let Some(b) = self.find_usable(bt.as_str(), &enabled).await {
                return Some(b);
            }
        }

        // Fallback: any usable backend
        for backend in &self.backends {
            let bt = backend.backend_type().as_str().to_string();
            if enabled.contains(&bt) && backend.is_available().await {
                return Some(backend.as_ref());
            }
        }

        log::warn!("No enabled and available backend found");
        None
    }

    async fn find_usable(
        &self,
        backend_type: &str,
        enabled: &std::collections::HashSet<String>,
    ) -> Option<&dyn CliBackend> {
        if !enabled.contains(backend_type) {
            return None;
        }
        for backend in &self.backends {
            if backend.backend_type().as_str() == backend_type && backend.is_available().await {
                return Some(backend.as_ref());
            }
        }
        None
    }
}
