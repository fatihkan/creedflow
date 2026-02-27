use crate::backends::detect::find_cli;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DetectedEditor {
    pub name: String,
    pub command: String,
    pub path: String,
}

/// Detect available code editors on the system.
pub fn detect_editors() -> Vec<DetectedEditor> {
    let candidates = [
        ("VS Code", "code"),
        ("Cursor", "cursor"),
        ("Zed", "zed"),
        ("Windsurf", "windsurf"),
        ("Sublime Text", "subl"),
        ("Neovim", "nvim"),
        ("Vim", "vim"),
    ];

    // Also check macOS .app bundle paths
    #[cfg(target_os = "macos")]
    let app_bundles: &[(&str, &str, &str)] = &[
        (
            "VS Code",
            "code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
        ),
        (
            "Cursor",
            "cursor",
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
        ),
        (
            "Zed",
            "zed",
            "/Applications/Zed.app/Contents/MacOS/cli",
        ),
        (
            "Windsurf",
            "windsurf",
            "/Applications/Windsurf.app/Contents/Resources/app/bin/windsurf",
        ),
        (
            "Sublime Text",
            "subl",
            "/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl",
        ),
    ];

    let mut editors = Vec::new();
    let mut found_names = std::collections::HashSet::new();

    // Check CLI commands via PATH
    for (name, cmd) in candidates {
        if let Some(path) = find_cli(cmd) {
            if found_names.insert(name.to_string()) {
                editors.push(DetectedEditor {
                    name: name.to_string(),
                    command: cmd.to_string(),
                    path,
                });
            }
        }
    }

    // Check macOS .app bundle paths for editors not found on PATH
    #[cfg(target_os = "macos")]
    {
        for (name, cmd, bundle_path) in app_bundles {
            if !found_names.contains(*name) && std::path::Path::new(bundle_path).exists() {
                found_names.insert(name.to_string());
                editors.push(DetectedEditor {
                    name: name.to_string(),
                    command: cmd.to_string(),
                    path: bundle_path.to_string(),
                });
            }
        }
    }

    editors
}
