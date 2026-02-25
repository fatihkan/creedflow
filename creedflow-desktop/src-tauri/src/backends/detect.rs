use std::path::PathBuf;

/// Find a CLI tool by name, checking common installation paths.
pub fn find_cli(name: &str) -> Option<String> {
    // First check if it's on PATH via `which` (Unix) or `where` (Windows)
    if let Ok(output) = std::process::Command::new(which_command())
        .arg(name)
        .output()
    {
        if output.status.success() {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() {
                return Some(path);
            }
        }
    }

    // Check common paths
    for candidate in candidates_for(name) {
        let expanded = expand_path(&candidate);
        if PathBuf::from(&expanded).exists() {
            return Some(expanded);
        }
    }

    None
}

fn which_command() -> &'static str {
    #[cfg(windows)]
    { "where" }
    #[cfg(not(windows))]
    { "which" }
}

fn candidates_for(name: &str) -> Vec<String> {
    let mut paths = Vec::new();

    #[cfg(unix)]
    {
        let home = dirs::home_dir().unwrap_or_default();
        paths.push(format!("{}/.local/bin/{}", home.display(), name));
        paths.push(format!("/usr/local/bin/{}", name));
        paths.push(format!("/opt/homebrew/bin/{}", name));
        paths.push(format!("/usr/bin/{}", name));
    }

    #[cfg(windows)]
    {
        if let Some(appdata) = dirs::config_dir() {
            paths.push(format!("{}\\npm\\{}.cmd", appdata.display(), name));
        }
        if let Some(local) = dirs::data_local_dir() {
            paths.push(format!("{}\\Programs\\{}.exe", local.display(), name));
        }
        paths.push(format!("C:\\Program Files\\{}\\{}.exe", capitalize(name), name));
        if let Some(home) = dirs::home_dir() {
            paths.push(format!("{}\\.local\\bin\\{}.exe", home.display(), name));
        }
    }

    paths
}

fn expand_path(path: &str) -> String {
    if path.starts_with('~') {
        if let Some(home) = dirs::home_dir() {
            return path.replacen('~', &home.to_string_lossy(), 1);
        }
    }
    path.to_string()
}

#[cfg(windows)]
fn capitalize(s: &str) -> String {
    let mut c = s.chars();
    match c.next() {
        None => String::new(),
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
    }
}
