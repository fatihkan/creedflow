use crate::backends;
use serde::{Deserialize, Serialize};
use tauri::State;
use crate::state::AppState;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackendInfo {
    pub backend_type: String,
    pub display_name: String,
    pub is_available: bool,
    pub is_enabled: bool,
    pub cli_path: Option<String>,
    pub color: String,
    pub is_local: bool,
}

#[tauri::command]
pub async fn list_backends() -> Result<Vec<BackendInfo>, String> {
    let backends = vec![
        BackendInfo {
            backend_type: "claude".into(),
            display_name: "Claude".into(),
            is_available: backends::detect::find_cli("claude").is_some(),
            is_enabled: true,
            cli_path: backends::detect::find_cli("claude"),
            color: "#8b5cf6".into(), // purple
            is_local: false,
        },
        BackendInfo {
            backend_type: "codex".into(),
            display_name: "Codex".into(),
            is_available: backends::detect::find_cli("codex").is_some(),
            is_enabled: true,
            cli_path: backends::detect::find_cli("codex"),
            color: "#22c55e".into(), // green
            is_local: false,
        },
        BackendInfo {
            backend_type: "gemini".into(),
            display_name: "Gemini".into(),
            is_available: backends::detect::find_cli("gemini").is_some(),
            is_enabled: true,
            cli_path: backends::detect::find_cli("gemini"),
            color: "#3b82f6".into(), // blue
            is_local: false,
        },
        BackendInfo {
            backend_type: "ollama".into(),
            display_name: "Ollama".into(),
            is_available: backends::detect::find_cli("ollama").is_some(),
            is_enabled: false,
            cli_path: backends::detect::find_cli("ollama"),
            color: "#f97316".into(), // orange
            is_local: true,
        },
        BackendInfo {
            backend_type: "lmStudio".into(),
            display_name: "LM Studio".into(),
            is_available: false, // Requires HTTP check
            is_enabled: false,
            cli_path: None,
            color: "#06b6d4".into(), // cyan
            is_local: true,
        },
        BackendInfo {
            backend_type: "llamaCpp".into(),
            display_name: "llama.cpp".into(),
            is_available: backends::detect::find_cli("llama-cli").is_some(),
            is_enabled: false,
            cli_path: backends::detect::find_cli("llama-cli"),
            color: "#ec4899".into(), // pink
            is_local: true,
        },
        BackendInfo {
            backend_type: "mlx".into(),
            display_name: "MLX".into(),
            is_available: backends::detect::find_cli("mlx_lm.generate").is_some(),
            is_enabled: false,
            cli_path: backends::detect::find_cli("mlx_lm.generate"),
            color: "#a3e635".into(), // mint/lime
            is_local: true,
        },
    ];
    Ok(backends)
}

#[tauri::command]
pub async fn check_backend(backend_type: String) -> Result<BackendInfo, String> {
    let backends = list_backends().await?;
    backends
        .into_iter()
        .find(|b| b.backend_type == backend_type)
        .ok_or_else(|| format!("Unknown backend: {}", backend_type))
}

#[tauri::command]
pub async fn toggle_backend(
    _state: State<'_, AppState>,
    backend_type: String,
    enabled: bool,
) -> Result<(), String> {
    // Settings are persisted via the settings command; this is a convenience wrapper
    log::info!("Backend {} set to enabled={}", backend_type, enabled);
    Ok(())
}
