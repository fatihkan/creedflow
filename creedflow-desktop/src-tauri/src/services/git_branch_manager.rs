use super::git::GitService;

/// Port of Swift's GitBranchManager — manages three-branch structure
/// (main → staging → dev) with feature branches and auto-commits.
pub struct GitBranchManager;

impl GitBranchManager {
    /// Ensure main/staging/dev branches exist, leaving repo on `dev`.
    pub async fn ensure_branch_structure(dir: &str) -> Result<(), String> {
        // Create main if not exists (usually already there)
        if !GitService::branch_exists(dir, "main").await {
            let _ = GitService::branch(dir, "main").await;
        }

        // Create staging from main
        if !GitService::branch_exists(dir, "staging").await {
            let _ = GitService::checkout(dir, "main").await;
            let _ = GitService::branch(dir, "staging").await;
        }

        // Create dev from staging
        if !GitService::branch_exists(dir, "dev").await {
            let _ = GitService::checkout(dir, "staging").await;
            let _ = GitService::branch(dir, "dev").await;
        }

        // Leave on dev
        let _ = GitService::checkout(dir, "dev").await;
        Ok(())
    }

    /// Create a feature branch from dev: feature/{task_id_prefix}-{title}
    pub async fn setup_feature_branch(
        dir: &str,
        task_id: &str,
        title: &str,
    ) -> Result<String, String> {
        let _ = GitService::checkout(dir, "dev").await;

        let prefix = &task_id[..8.min(task_id.len())];
        let slug: String = title
            .to_lowercase()
            .chars()
            .map(|c| if c.is_alphanumeric() { c } else { '-' })
            .collect::<String>()
            .trim_matches('-')
            .to_string();
        let slug = if slug.len() > 40 { &slug[..40] } else { &slug };
        let branch_name = format!("feature/{}-{}", prefix, slug);

        GitService::branch(dir, &branch_name).await?;
        Ok(branch_name)
    }

    /// Auto-commit if there are changes, using conventional commit prefix.
    pub async fn auto_commit_if_needed(
        dir: &str,
        task_id: &str,
        title: &str,
        agent_type: &str,
    ) -> Result<Option<String>, String> {
        if !GitService::has_changes(dir).await {
            return Ok(None);
        }

        let prefix = match agent_type {
            "coder" => "feat",
            "tester" => "test",
            "devops" => "ops",
            "contentWriter" => "docs",
            "designer" => "design",
            "imageGenerator" | "videoEditor" => "asset",
            "publisher" => "content",
            _ => "chore",
        };

        let short_id = &task_id[..8.min(task_id.len())];
        let message = format!("{}: {} [{}]", prefix, title, short_id);

        GitService::add_all(dir).await?;
        GitService::commit(dir, &message).await?;
        let hash = GitService::latest_commit_hash(dir).await?;
        Ok(Some(hash))
    }

    /// Create a PR from feature branch to dev.
    pub async fn create_feature_pr(
        dir: &str,
        branch: &str,
        title: &str,
    ) -> Result<String, String> {
        GitService::push(dir, "origin", branch).await?;
        GitService::create_pr_via_gh(dir, title, "", "dev", branch).await
    }

    /// Squash-merge a feature branch into dev, then delete the branch.
    pub async fn merge_feature_to_dev(dir: &str, branch: &str) -> Result<(), String> {
        GitService::checkout(dir, "dev").await?;
        GitService::merge(dir, branch, true).await?;
        let msg = format!("merge: {} into dev", branch);
        GitService::commit(dir, &msg).await?;

        // Clean up: delete the feature branch after successful merge
        if let Err(e) = GitService::delete_branch(dir, branch).await {
            log::warn!("Could not delete branch {}: {}", branch, e);
        } else {
            log::info!("Deleted branch {} after merge", branch);
        }

        Ok(())
    }

    /// Promote dev to staging via PR.
    pub async fn promote_dev_to_staging(dir: &str) -> Result<String, String> {
        GitService::push(dir, "origin", "dev").await?;
        GitService::create_pr_via_gh(
            dir,
            "Promote dev to staging",
            "All feature tasks passed — promoting to staging.",
            "staging",
            "dev",
        )
        .await
    }

    /// Promote staging to main via PR.
    pub async fn promote_staging_to_main(dir: &str) -> Result<String, String> {
        GitService::push(dir, "origin", "staging").await?;
        GitService::create_pr_via_gh(
            dir,
            "Release staging to main",
            "Staging deploy successful — promoting to production.",
            "main",
            "staging",
        )
        .await
    }
}
