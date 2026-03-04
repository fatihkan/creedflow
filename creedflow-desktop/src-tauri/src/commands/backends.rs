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

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DependencyStatus {
    pub name: String,
    pub display_name: String,
    pub category: String,
    pub installed: bool,
    pub version: Option<String>,
    pub path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PackageManagerInfo {
    pub name: String,
    pub display_name: String,
    pub available: bool,
}

// ─── Package Manager Detection ───────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq)]
enum PackageManager {
    Brew,
    Apt,
    Dnf,
    Pacman,
    None,
}

impl PackageManager {
    fn name(&self) -> &str {
        match self {
            Self::Brew => "brew",
            Self::Apt => "apt",
            Self::Dnf => "dnf",
            Self::Pacman => "pacman",
            Self::None => "none",
        }
    }

    fn display_name(&self) -> &str {
        match self {
            Self::Brew => "Homebrew",
            Self::Apt => "APT",
            Self::Dnf => "DNF",
            Self::Pacman => "Pacman",
            Self::None => "None",
        }
    }
}

fn detect_package_manager() -> PackageManager {
    #[cfg(target_os = "macos")]
    {
        if backends::detect::find_cli("brew").is_some() {
            return PackageManager::Brew;
        }
    }

    #[cfg(target_os = "linux")]
    {
        if backends::detect::find_cli("apt").is_some() {
            return PackageManager::Apt;
        }
        if backends::detect::find_cli("dnf").is_some() {
            return PackageManager::Dnf;
        }
        if backends::detect::find_cli("pacman").is_some() {
            return PackageManager::Pacman;
        }
        if backends::detect::find_cli("brew").is_some() {
            return PackageManager::Brew; // Linuxbrew
        }
    }

    PackageManager::None
}

/// Returns the package name for a given dependency and package manager.
fn package_name_for(dep: &str, pm: PackageManager) -> Option<&'static str> {
    match (dep, pm) {
        // git
        ("git", PackageManager::Brew) => Some("git"),
        ("git", PackageManager::Apt) => Some("git"),
        ("git", PackageManager::Dnf) => Some("git"),
        ("git", PackageManager::Pacman) => Some("git"),
        // docker
        ("docker", PackageManager::Brew) => Some("docker"),
        ("docker", PackageManager::Apt) => Some("docker.io"),
        ("docker", PackageManager::Dnf) => Some("docker"),
        ("docker", PackageManager::Pacman) => Some("docker"),
        // gh
        ("gh", PackageManager::Brew) => Some("gh"),
        ("gh", PackageManager::Apt) => Some("gh"),
        ("gh", PackageManager::Dnf) => Some("gh"),
        ("gh", PackageManager::Pacman) => Some("github-cli"),
        // node
        ("node", PackageManager::Brew) => Some("node"),
        ("node", PackageManager::Apt) => Some("nodejs"),
        ("node", PackageManager::Dnf) => Some("nodejs"),
        ("node", PackageManager::Pacman) => Some("nodejs"),
        // python3
        ("python3", PackageManager::Brew) => Some("python"),
        ("python3", PackageManager::Apt) => Some("python3"),
        ("python3", PackageManager::Dnf) => Some("python3"),
        ("python3", PackageManager::Pacman) => Some("python"),
        // go
        ("go", PackageManager::Brew) => Some("go"),
        ("go", PackageManager::Apt) => Some("golang"),
        ("go", PackageManager::Dnf) => Some("golang"),
        ("go", PackageManager::Pacman) => Some("go"),
        // ollama
        ("ollama", PackageManager::Brew) => Some("ollama"),
        _ => None,
    }
}

// ─── Tauri Commands ──────────────────────────────────────────────────────────

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
        BackendInfo {
            backend_type: "opencode".into(),
            display_name: "OpenCode".into(),
            is_available: backends::detect::find_cli("opencode").is_some(),
            is_enabled: false,
            cli_path: backends::detect::find_cli("opencode"),
            color: "#14b8a6".into(), // teal
            is_local: false,
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

#[tauri::command]
pub async fn detect_package_manager_cmd() -> Result<PackageManagerInfo, String> {
    let pm = detect_package_manager();
    Ok(PackageManagerInfo {
        name: pm.name().to_string(),
        display_name: pm.display_name().to_string(),
        available: pm != PackageManager::None,
    })
}

#[tauri::command]
pub async fn detect_dependencies() -> Result<Vec<DependencyStatus>, String> {
    let deps: Vec<(&str, &str, &str)> = vec![
        // Core tools
        ("git", "Git", "core"),
        ("docker", "Docker", "core"),
        ("gh", "GitHub CLI", "core"),
        ("node", "Node.js", "core"),
        ("python3", "Python 3", "core"),
        ("go", "Go", "core"),
        // AI CLIs
        ("claude", "Claude", "ai"),
        ("codex", "Codex", "ai"),
        ("gemini", "Gemini", "ai"),
        ("ollama", "Ollama", "ai"),
        ("opencode", "OpenCode", "ai"),
        ("llama-cli", "llama.cpp", "ai"),
        // Editors
        ("code", "VS Code", "editor"),
        ("cursor", "Cursor", "editor"),
        ("zed", "Zed", "editor"),
        ("windsurf", "Windsurf", "editor"),
        // Platform-specific build tools
        #[cfg(target_os = "macos")]
        ("xcode-select", "Xcode CLI Tools", "platform"),
        #[cfg(target_os = "linux")]
        ("gcc", "Build Essential", "platform"),
    ];

    // Also detect package manager
    let pm = detect_package_manager();
    let mut results = Vec::new();

    // Add package manager as first entry
    results.push(DependencyStatus {
        name: pm.name().to_string(),
        display_name: pm.display_name().to_string(),
        category: "package_manager".to_string(),
        installed: pm != PackageManager::None,
        version: None,
        path: if pm != PackageManager::None {
            backends::detect::find_cli(pm.name())
        } else {
            None
        },
    });

    for (name, display_name, category) in deps {
        let path = backends::detect::find_cli(name);
        let installed = path.is_some();
        let version = if installed {
            get_version(name).await.ok()
        } else {
            None
        };
        results.push(DependencyStatus {
            name: name.to_string(),
            display_name: display_name.to_string(),
            category: category.to_string(),
            installed,
            version,
            path,
        });
    }
    Ok(results)
}

#[tauri::command]
pub async fn install_dependency(name: String) -> Result<String, String> {
    use tokio::process::Command;

    // CLI-specific install instructions (no package manager needed)
    match name.as_str() {
        "claude" => return Err("Install Claude CLI from https://claude.ai/cli".to_string()),
        "codex" => {
            return Err(
                "Install Codex CLI via npm: npm install -g @openai/codex".to_string(),
            )
        }
        "gemini" => {
            return Err(
                "Install Gemini CLI via npm: npm install -g @google/gemini-cli".to_string(),
            )
        }
        "opencode" => {
            return Err(
                "Install OpenCode CLI: see https://github.com/nicholasgriffintn/opencode".to_string(),
            )
        }
        _ => {}
    }

    let pm = detect_package_manager();
    if pm == PackageManager::None {
        return Err(format!(
            "No package manager found. Install {} manually.\n\
             macOS: Install Homebrew from https://brew.sh\n\
             Linux: Use apt, dnf, or pacman",
            name
        ));
    }

    let package = match package_name_for(&name, pm) {
        Some(pkg) => pkg,
        None => {
            return Err(format!(
                "{} cannot be installed via {}. Install it manually.",
                name,
                pm.display_name()
            ))
        }
    };

    let (cmd, args): (&str, Vec<&str>) = match pm {
        PackageManager::Brew => ("brew", vec!["install", package]),
        PackageManager::Apt => ("sudo", vec!["apt", "install", "-y", package]),
        PackageManager::Dnf => ("sudo", vec!["dnf", "install", "-y", package]),
        PackageManager::Pacman => ("sudo", vec!["pacman", "-S", "--noconfirm", package]),
        PackageManager::None => unreachable!(),
    };

    log::info!(
        "Installing {} via {} (package: {})",
        name,
        pm.display_name(),
        package
    );

    let output = Command::new(cmd)
        .args(&args)
        .output()
        .await
        .map_err(|e| format!("{} install failed: {}", pm.display_name(), e))?;

    if output.status.success() {
        Ok(format!(
            "Successfully installed {} via {}",
            name,
            pm.display_name()
        ))
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        Err(if stderr.is_empty() { stdout } else { stderr })
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ComparisonResult {
    pub backend_type: String,
    pub output: String,
    pub duration_ms: u64,
    pub error: Option<String>,
}

#[tauri::command]
pub async fn compare_backends(prompt: String, backend_types: Vec<String>) -> Result<Vec<ComparisonResult>, String> {
    use tokio::process::Command;
    use std::time::Instant;

    let mut handles = Vec::new();
    for bt in backend_types {
        let prompt = prompt.clone();
        handles.push(tokio::spawn(async move {
            let start = Instant::now();
            let cli = match bt.as_str() {
                "claude" => "claude",
                "codex" => "codex",
                "gemini" => "gemini",
                "opencode" => "opencode",
                "openclaw" => "openclaw",
                _ => return ComparisonResult {
                    backend_type: bt,
                    output: String::new(),
                    duration_ms: 0,
                    error: Some("Unknown backend".into()),
                },
            };

            let args: Vec<String> = match bt.as_str() {
                "claude" => vec!["-p".into(), prompt.clone(), "--output-format".into(), "text".into()],
                "codex" => vec!["exec".into(), prompt.clone(), "--full-auto".into()],
                "gemini" => vec!["-p".into(), prompt.clone(), "-y".into(), "-o".into(), "text".into()],
                "opencode" => vec!["run".into(), prompt.clone(), "-q".into()],
                "openclaw" => vec!["agent".into(), "--message".into(), prompt.clone(), "--format".into(), "text".into()],
                _ => vec![prompt.clone()],
            };

            match Command::new(cli)
                .args(&args)
                .env("PATH", std::env::var("PATH").unwrap_or_default())
                .output()
                .await
            {
                Ok(output) => {
                    let elapsed = start.elapsed().as_millis() as u64;
                    if output.status.success() {
                        ComparisonResult {
                            backend_type: bt,
                            output: String::from_utf8_lossy(&output.stdout).to_string(),
                            duration_ms: elapsed,
                            error: None,
                        }
                    } else {
                        ComparisonResult {
                            backend_type: bt,
                            output: String::from_utf8_lossy(&output.stdout).to_string(),
                            duration_ms: elapsed,
                            error: Some(String::from_utf8_lossy(&output.stderr).to_string()),
                        }
                    }
                }
                Err(e) => ComparisonResult {
                    backend_type: bt,
                    output: String::new(),
                    duration_ms: start.elapsed().as_millis() as u64,
                    error: Some(e.to_string()),
                },
            }
        }));
    }

    let mut results = Vec::new();
    for handle in handles {
        match handle.await {
            Ok(result) => results.push(result),
            Err(e) => results.push(ComparisonResult {
                backend_type: "unknown".into(),
                output: String::new(),
                duration_ms: 0,
                error: Some(e.to_string()),
            }),
        }
    }
    Ok(results)
}

#[tauri::command]
pub async fn export_comparison(results: Vec<ComparisonResult>, dest_path: String) -> Result<(), String> {
    let json = serde_json::to_string_pretty(&results)
        .map_err(|e| format!("Failed to serialize results: {}", e))?;
    std::fs::write(&dest_path, json)
        .map_err(|e| format!("Failed to write file: {}", e))?;
    Ok(())
}

async fn get_version(name: &str) -> Result<String, String> {
    use tokio::process::Command;

    let (cmd, args): (&str, &[&str]) = match name {
        "git" => ("git", &["--version"]),
        "docker" => ("docker", &["--version"]),
        "gh" => ("gh", &["--version"]),
        "node" => ("node", &["--version"]),
        "python3" => ("python3", &["--version"]),
        "go" => ("go", &["version"]),
        "brew" => ("brew", &["--version"]),
        "claude" => ("claude", &["--version"]),
        "codex" => ("codex", &["--version"]),
        "gemini" => ("gemini", &["--version"]),
        "ollama" => ("ollama", &["--version"]),
        "opencode" => ("opencode", &["--version"]),
        "llama-cli" => ("llama-cli", &["--version"]),
        "code" => ("code", &["--version"]),
        "cursor" => ("cursor", &["--version"]),
        "zed" => ("zed", &["--version"]),
        "windsurf" => ("windsurf", &["--version"]),
        #[cfg(target_os = "macos")]
        "xcode-select" => ("xcode-select", &["--version"]),
        #[cfg(target_os = "linux")]
        "gcc" => ("gcc", &["--version"]),
        _ => return Err("Unknown".to_string()),
    };

    let output = Command::new(cmd)
        .args(args)
        .output()
        .await
        .map_err(|e| e.to_string())?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout)
            .trim()
            .lines()
            .next()
            .unwrap_or("")
            .to_string())
    } else {
        Err("Failed to get version".to_string())
    }
}
