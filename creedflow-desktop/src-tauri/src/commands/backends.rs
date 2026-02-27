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
    Winget,
    Choco,
    Scoop,
    None,
}

impl PackageManager {
    fn name(&self) -> &str {
        match self {
            Self::Brew => "brew",
            Self::Apt => "apt",
            Self::Dnf => "dnf",
            Self::Pacman => "pacman",
            Self::Winget => "winget",
            Self::Choco => "choco",
            Self::Scoop => "scoop",
            Self::None => "none",
        }
    }

    fn display_name(&self) -> &str {
        match self {
            Self::Brew => "Homebrew",
            Self::Apt => "APT",
            Self::Dnf => "DNF",
            Self::Pacman => "Pacman",
            Self::Winget => "WinGet",
            Self::Choco => "Chocolatey",
            Self::Scoop => "Scoop",
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

    #[cfg(target_os = "windows")]
    {
        if backends::detect::find_cli("winget").is_some() {
            return PackageManager::Winget;
        }
        if backends::detect::find_cli("choco").is_some() {
            return PackageManager::Choco;
        }
        if backends::detect::find_cli("scoop").is_some() {
            return PackageManager::Scoop;
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
        ("git", PackageManager::Winget) => Some("Git.Git"),
        ("git", PackageManager::Choco) => Some("git"),
        ("git", PackageManager::Scoop) => Some("git"),
        // docker
        ("docker", PackageManager::Brew) => Some("docker"),
        ("docker", PackageManager::Apt) => Some("docker.io"),
        ("docker", PackageManager::Dnf) => Some("docker"),
        ("docker", PackageManager::Pacman) => Some("docker"),
        ("docker", PackageManager::Winget) => Some("Docker.DockerDesktop"),
        ("docker", PackageManager::Choco) => Some("docker-desktop"),
        // gh
        ("gh", PackageManager::Brew) => Some("gh"),
        ("gh", PackageManager::Apt) => Some("gh"),
        ("gh", PackageManager::Dnf) => Some("gh"),
        ("gh", PackageManager::Pacman) => Some("github-cli"),
        ("gh", PackageManager::Winget) => Some("GitHub.cli"),
        ("gh", PackageManager::Choco) => Some("gh"),
        ("gh", PackageManager::Scoop) => Some("gh"),
        // node
        ("node", PackageManager::Brew) => Some("node"),
        ("node", PackageManager::Apt) => Some("nodejs"),
        ("node", PackageManager::Dnf) => Some("nodejs"),
        ("node", PackageManager::Pacman) => Some("nodejs"),
        ("node", PackageManager::Winget) => Some("OpenJS.NodeJS"),
        ("node", PackageManager::Choco) => Some("nodejs"),
        ("node", PackageManager::Scoop) => Some("nodejs"),
        // python3
        ("python3", PackageManager::Brew) => Some("python"),
        ("python3", PackageManager::Apt) => Some("python3"),
        ("python3", PackageManager::Dnf) => Some("python3"),
        ("python3", PackageManager::Pacman) => Some("python"),
        ("python3", PackageManager::Winget) => Some("Python.Python.3.12"),
        ("python3", PackageManager::Choco) => Some("python3"),
        ("python3", PackageManager::Scoop) => Some("python"),
        // go
        ("go", PackageManager::Brew) => Some("go"),
        ("go", PackageManager::Apt) => Some("golang"),
        ("go", PackageManager::Dnf) => Some("golang"),
        ("go", PackageManager::Pacman) => Some("go"),
        ("go", PackageManager::Winget) => Some("GoLang.Go"),
        ("go", PackageManager::Choco) => Some("golang"),
        ("go", PackageManager::Scoop) => Some("go"),
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
        _ => {}
    }

    let pm = detect_package_manager();
    if pm == PackageManager::None {
        return Err(format!(
            "No package manager found. Install {} manually.\n\
             macOS: Install Homebrew from https://brew.sh\n\
             Linux: Use apt, dnf, or pacman\n\
             Windows: Install winget, choco, or scoop",
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
        PackageManager::Winget => ("winget", vec!["install", "--id", package, "-e", "--accept-source-agreements"]),
        PackageManager::Choco => ("choco", vec!["install", package, "-y"]),
        PackageManager::Scoop => ("scoop", vec!["install", package]),
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
