use tokio::process::Command;

/// Git CLI wrapper — all git operations via tokio::process
pub struct GitService;

impl GitService {
    pub async fn init(dir: &str) -> Result<String, String> {
        run_git(dir, &["init"]).await
    }

    pub async fn branch(dir: &str, name: &str) -> Result<String, String> {
        run_git(dir, &["checkout", "-b", name]).await
    }

    pub async fn checkout(dir: &str, name: &str) -> Result<String, String> {
        run_git(dir, &["checkout", name]).await
    }

    pub async fn branch_exists(dir: &str, name: &str) -> bool {
        run_git(dir, &["rev-parse", "--verify", name]).await.is_ok()
    }

    pub async fn has_changes(dir: &str) -> bool {
        run_git(dir, &["status", "--porcelain"]).await
            .map(|s| !s.is_empty())
            .unwrap_or(false)
    }

    pub async fn add_all(dir: &str) -> Result<String, String> {
        run_git(dir, &["add", "-A"]).await
    }

    pub async fn commit(dir: &str, message: &str) -> Result<String, String> {
        run_git(dir, &["commit", "-m", message]).await
    }

    pub async fn push(dir: &str, remote: &str, branch: &str) -> Result<String, String> {
        run_git(dir, &["push", remote, branch]).await
    }

    pub async fn delete_branch(dir: &str, name: &str) -> Result<String, String> {
        run_git(dir, &["branch", "-D", name]).await
    }

    pub async fn current_branch(dir: &str) -> Result<String, String> {
        run_git(dir, &["rev-parse", "--abbrev-ref", "HEAD"]).await
    }

    pub async fn latest_commit_hash(dir: &str) -> Result<String, String> {
        run_git(dir, &["rev-parse", "HEAD"]).await
    }

    pub async fn merge(dir: &str, branch: &str, squash: bool) -> Result<String, String> {
        if squash {
            run_git(dir, &["merge", "--squash", branch]).await
        } else {
            run_git(dir, &["merge", branch]).await
        }
    }

    pub async fn create_pr_via_gh(
        dir: &str,
        title: &str,
        body: &str,
        base: &str,
        head: &str,
    ) -> Result<String, String> {
        let output = Command::new("gh")
            .args(["pr", "create", "--title", title, "--body", body, "--base", base, "--head", head])
            .current_dir(dir)
            .output()
            .await
            .map_err(|e| format!("gh error: {}", e))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
        }
    }
}

async fn run_git(dir: &str, args: &[&str]) -> Result<String, String> {
    let output = Command::new("git")
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
