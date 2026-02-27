use crate::db::models::Project;
use crate::services::git::GitService;
use crate::services::git_branch_manager::GitBranchManager;
use crate::state::AppState;
use tauri::State;

#[tauri::command]
pub async fn git_ensure_branch_structure(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<(), String> {
    let dir = get_project_dir(&state, &project_id).await?;
    GitBranchManager::ensure_branch_structure(&dir).await
}

#[tauri::command]
pub async fn git_setup_feature_branch(
    state: State<'_, AppState>,
    project_id: String,
    task_id: String,
    title: String,
) -> Result<String, String> {
    let dir = get_project_dir(&state, &project_id).await?;
    GitBranchManager::setup_feature_branch(&dir, &task_id, &title).await
}

#[tauri::command]
pub async fn git_auto_commit(
    state: State<'_, AppState>,
    project_id: String,
    task_id: String,
    title: String,
    agent_type: String,
) -> Result<Option<String>, String> {
    let dir = get_project_dir(&state, &project_id).await?;
    GitBranchManager::auto_commit_if_needed(&dir, &task_id, &title, &agent_type).await
}

#[tauri::command]
pub async fn git_merge_feature_to_dev(
    state: State<'_, AppState>,
    project_id: String,
    branch_name: String,
) -> Result<(), String> {
    let dir = get_project_dir(&state, &project_id).await?;
    GitBranchManager::merge_feature_to_dev(&dir, &branch_name).await
}

#[tauri::command]
pub async fn git_promote_dev_to_staging(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<String, String> {
    let dir = get_project_dir(&state, &project_id).await?;
    GitBranchManager::promote_dev_to_staging(&dir).await
}

#[tauri::command]
pub async fn git_promote_staging_to_main(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<String, String> {
    let dir = get_project_dir(&state, &project_id).await?;
    GitBranchManager::promote_staging_to_main(&dir).await
}

#[tauri::command]
pub async fn git_current_branch(
    state: State<'_, AppState>,
    project_id: String,
) -> Result<String, String> {
    let dir = get_project_dir(&state, &project_id).await?;
    GitService::current_branch(&dir).await
}

#[tauri::command]
pub async fn git_log(
    state: State<'_, AppState>,
    project_id: String,
    count: Option<u32>,
) -> Result<Vec<GitLogEntry>, String> {
    let dir = get_project_dir(&state, &project_id).await?;
    let n = count.unwrap_or(50);
    let format = "%H|%P|%D|%an|%at|%s";
    let output = run_git_raw(&dir, &["log", "--all", &format!("--format={}", format), &format!("-{}", n)]).await?;

    let entries: Vec<GitLogEntry> = output
        .lines()
        .filter(|l| !l.is_empty())
        .filter_map(|line| {
            let parts: Vec<&str> = line.splitn(6, '|').collect();
            if parts.len() < 6 { return None; }
            Some(GitLogEntry {
                hash: parts[0].to_string(),
                short_hash: parts[0][..7.min(parts[0].len())].to_string(),
                parents: parts[1].split_whitespace().map(|s| s.to_string()).collect(),
                decorations: parts[2].to_string(),
                author: parts[3].to_string(),
                timestamp: parts[4].parse().unwrap_or(0),
                message: parts[5].to_string(),
            })
        })
        .collect();

    Ok(entries)
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitLogEntry {
    pub hash: String,
    pub short_hash: String,
    pub parents: Vec<String>,
    pub decorations: String,
    pub author: String,
    pub timestamp: i64,
    pub message: String,
}

// ─── Git Config ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitConfig {
    pub user_name: String,
    pub user_email: String,
    pub git_installed: bool,
    pub git_version: String,
    pub gh_installed: bool,
    pub gh_version: String,
}

#[tauri::command]
pub async fn get_git_config() -> Result<GitConfig, String> {
    let git_version = tokio::process::Command::new("git")
        .args(["--version"])
        .output()
        .await
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();

    let git_installed = !git_version.is_empty();

    let user_name = if git_installed {
        tokio::process::Command::new("git")
            .args(["config", "--global", "user.name"])
            .output()
            .await
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_default()
    } else {
        String::new()
    };

    let user_email = if git_installed {
        tokio::process::Command::new("git")
            .args(["config", "--global", "user.email"])
            .output()
            .await
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_default()
    } else {
        String::new()
    };

    let gh_version = tokio::process::Command::new("gh")
        .args(["--version"])
        .output()
        .await
        .ok()
        .filter(|o| o.status.success())
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .next()
                .unwrap_or("")
                .trim()
                .to_string()
        })
        .unwrap_or_default();

    let gh_installed = !gh_version.is_empty();

    Ok(GitConfig {
        user_name,
        user_email,
        git_installed,
        git_version,
        gh_installed,
        gh_version,
    })
}

#[tauri::command]
pub async fn set_git_config(name: String, email: String) -> Result<(), String> {
    if !name.is_empty() {
        tokio::process::Command::new("git")
            .args(["config", "--global", "user.name", &name])
            .output()
            .await
            .map_err(|e| format!("Failed to set git user.name: {}", e))?;
    }
    if !email.is_empty() {
        tokio::process::Command::new("git")
            .args(["config", "--global", "user.email", &email])
            .output()
            .await
            .map_err(|e| format!("Failed to set git user.email: {}", e))?;
    }
    Ok(())
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

async fn get_project_dir(state: &State<'_, AppState>, project_id: &str) -> Result<String, String> {
    let db = state.db.lock().await;
    let project = Project::get(&db.conn, project_id)
        .map_err(|e| format!("Project not found: {}", e))?;
    if project.directory_path.is_empty() {
        return Err("Project has no directory path".to_string());
    }
    Ok(project.directory_path)
}

async fn run_git_raw(dir: &str, args: &[&str]) -> Result<String, String> {
    let output = tokio::process::Command::new("git")
        .args(args)
        .current_dir(dir)
        .output()
        .await
        .map_err(|e| format!("git error: {}", e))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}
