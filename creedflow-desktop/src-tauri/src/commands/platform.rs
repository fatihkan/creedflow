use crate::services::editor_detector::{self, DetectedEditor};
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use std::fs;
use tauri::{Manager, State};

// ─── Terminal ────────────────────────────────────────────────────────────────

#[tauri::command]
pub async fn open_terminal(path: String) -> Result<(), String> {
    let dir = std::path::Path::new(&path);
    if !dir.exists() {
        return Err(format!("Directory does not exist: {}", path));
    }

    #[cfg(target_os = "macos")]
    {
        tokio::process::Command::new("open")
            .args(["-a", "Terminal", &path])
            .spawn()
            .map_err(|e| format!("Failed to open Terminal: {}", e))?;
        return Ok(());
    }

    #[cfg(target_os = "linux")]
    {
        use crate::backends::detect::find_cli;
        let terminals = [
            ("x-terminal-emulator", &["--working-directory", &path] as &[&str]),
            ("gnome-terminal", &["--working-directory", &path]),
            ("konsole", &["--workdir", &path]),
            ("xfce4-terminal", &["--working-directory", &path]),
            ("xterm", &["-e", "cd", &path, "&&", "bash"]),
        ];
        for (term, args) in terminals {
            if find_cli(term).is_some() {
                tokio::process::Command::new(term)
                    .args(args)
                    .spawn()
                    .map_err(|e| format!("Failed to open {}: {}", term, e))?;
                return Ok(());
            }
        }
        return Err("No terminal emulator found. Install gnome-terminal, konsole, or xterm.".to_string());
    }

    #[cfg(target_os = "windows")]
    {
        tokio::process::Command::new("cmd")
            .args(["/c", "start", "wt", "-d", &path])
            .spawn()
            .or_else(|_| {
                tokio::process::Command::new("cmd")
                    .args(["/c", "start", "cmd", "/k", &format!("cd /d {}", path)])
                    .spawn()
            })
            .map_err(|e| format!("Failed to open terminal: {}", e))?;
        return Ok(());
    }

    #[allow(unreachable_code)]
    Err("Unsupported platform".to_string())
}

// ─── File Manager ────────────────────────────────────────────────────────────

#[tauri::command]
pub async fn open_in_file_manager(path: String) -> Result<(), String> {
    let target = std::path::Path::new(&path);
    if !target.exists() {
        return Err(format!("Path does not exist: {}", path));
    }

    #[cfg(target_os = "macos")]
    {
        tokio::process::Command::new("open")
            .arg(&path)
            .spawn()
            .map_err(|e| format!("Failed to open Finder: {}", e))?;
    }

    #[cfg(target_os = "linux")]
    {
        tokio::process::Command::new("xdg-open")
            .arg(&path)
            .spawn()
            .map_err(|e| format!("Failed to open file manager: {}", e))?;
    }

    #[cfg(target_os = "windows")]
    {
        tokio::process::Command::new("explorer")
            .arg(&path)
            .spawn()
            .map_err(|e| format!("Failed to open Explorer: {}", e))?;
    }

    Ok(())
}

// ─── URL ─────────────────────────────────────────────────────────────────────

#[tauri::command]
pub async fn open_url(url: String) -> Result<(), String> {
    open::that(&url).map_err(|e| format!("Failed to open URL: {}", e))
}

// ─── Editor ──────────────────────────────────────────────────────────────────

#[tauri::command]
pub async fn detect_editors() -> Result<Vec<DetectedEditor>, String> {
    Ok(editor_detector::detect_editors())
}

#[tauri::command]
pub async fn open_in_editor(path: String, editor_command: String) -> Result<(), String> {
    let target = std::path::Path::new(&path);
    if !target.exists() {
        return Err(format!("Path does not exist: {}", path));
    }

    tokio::process::Command::new(&editor_command)
        .arg(&path)
        .spawn()
        .map_err(|e| format!("Failed to open {} in {}: {}", path, editor_command, e))?;

    Ok(())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PlatformSettings {
    #[serde(skip_serializing_if = "Option::is_none")]
    preferred_editor: Option<String>,
}

fn platform_settings_path(app_handle: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
    let dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| format!("Failed to get app data dir: {}", e))?;
    fs::create_dir_all(&dir).map_err(|e| format!("Failed to create app data dir: {}", e))?;
    Ok(dir.join("platform_settings.json"))
}

fn read_platform_settings(app_handle: &tauri::AppHandle) -> PlatformSettings {
    let path = match platform_settings_path(app_handle) {
        Ok(p) => p,
        Err(_) => return PlatformSettings { preferred_editor: None },
    };
    if path.exists() {
        fs::read_to_string(&path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or(PlatformSettings { preferred_editor: None })
    } else {
        PlatformSettings { preferred_editor: None }
    }
}

fn write_platform_settings(
    app_handle: &tauri::AppHandle,
    settings: &PlatformSettings,
) -> Result<(), String> {
    let path = platform_settings_path(app_handle)?;
    let json = serde_json::to_string_pretty(settings)
        .map_err(|e| format!("Failed to serialize: {}", e))?;
    fs::write(&path, json).map_err(|e| format!("Failed to write: {}", e))
}

#[tauri::command]
pub async fn get_preferred_editor(state: State<'_, AppState>) -> Result<Option<String>, String> {
    Ok(read_platform_settings(&state.app_handle).preferred_editor)
}

#[tauri::command]
pub async fn set_preferred_editor(
    state: State<'_, AppState>,
    editor_command: Option<String>,
) -> Result<(), String> {
    let mut settings = read_platform_settings(&state.app_handle);
    settings.preferred_editor = editor_command;
    write_platform_settings(&state.app_handle, &settings)
}

// ─── Platform Info ───────────────────────────────────────────────────────────

#[tauri::command]
pub fn get_platform() -> String {
    #[cfg(target_os = "macos")]
    { return "macos".to_string(); }
    #[cfg(target_os = "linux")]
    { return "linux".to_string(); }
    #[cfg(target_os = "windows")]
    { return "windows".to_string(); }
    #[allow(unreachable_code)]
    "unknown".to_string()
}
