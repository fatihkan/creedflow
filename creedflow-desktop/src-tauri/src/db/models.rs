use rusqlite::{params, Connection, Row};
use serde::{Deserialize, Serialize};

// ─── Enums ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ProjectStatus {
    Planning,
    Analyzing,
    InProgress,
    Reviewing,
    Deploying,
    Completed,
    Failed,
    Paused,
}

impl ProjectStatus {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Planning => "planning",
            Self::Analyzing => "analyzing",
            Self::InProgress => "in_progress",
            Self::Reviewing => "reviewing",
            Self::Deploying => "deploying",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Paused => "paused",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "planning" => Self::Planning,
            "analyzing" => Self::Analyzing,
            "in_progress" => Self::InProgress,
            "reviewing" => Self::Reviewing,
            "deploying" => Self::Deploying,
            "completed" => Self::Completed,
            "failed" => Self::Failed,
            "paused" => Self::Paused,
            _ => Self::Planning,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ProjectType {
    Software,
    Content,
    Image,
    Video,
    Automation,
    General,
}

impl ProjectType {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Software => "software",
            Self::Content => "content",
            Self::Image => "image",
            Self::Video => "video",
            Self::Automation => "automation",
            Self::General => "general",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "software" => Self::Software,
            "content" => Self::Content,
            "image" => Self::Image,
            "video" => Self::Video,
            "automation" => Self::Automation,
            "general" => Self::General,
            _ => Self::Software,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AgentType {
    Analyzer,
    Coder,
    Reviewer,
    Tester,
    Devops,
    Monitor,
    ContentWriter,
    Designer,
    ImageGenerator,
    VideoEditor,
    Publisher,
    Planner,
}

impl AgentType {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Analyzer => "analyzer",
            Self::Coder => "coder",
            Self::Reviewer => "reviewer",
            Self::Tester => "tester",
            Self::Devops => "devops",
            Self::Monitor => "monitor",
            Self::ContentWriter => "contentWriter",
            Self::Designer => "designer",
            Self::ImageGenerator => "imageGenerator",
            Self::VideoEditor => "videoEditor",
            Self::Publisher => "publisher",
            Self::Planner => "planner",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "analyzer" => Self::Analyzer,
            "coder" => Self::Coder,
            "reviewer" => Self::Reviewer,
            "tester" => Self::Tester,
            "devops" => Self::Devops,
            "monitor" => Self::Monitor,
            "contentWriter" => Self::ContentWriter,
            "designer" => Self::Designer,
            "imageGenerator" => Self::ImageGenerator,
            "videoEditor" => Self::VideoEditor,
            "publisher" => Self::Publisher,
            "planner" => Self::Planner,
            _ => Self::Analyzer,
        }
    }

    pub fn all() -> Vec<Self> {
        vec![
            Self::Analyzer, Self::Coder, Self::Reviewer, Self::Tester,
            Self::Devops, Self::Monitor, Self::ContentWriter, Self::Designer,
            Self::ImageGenerator, Self::VideoEditor, Self::Publisher,
            Self::Planner,
        ]
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Queued,
    InProgress,
    Passed,
    Failed,
    NeedsRevision,
    Cancelled,
}

impl TaskStatus {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Queued => "queued",
            Self::InProgress => "in_progress",
            Self::Passed => "passed",
            Self::Failed => "failed",
            Self::NeedsRevision => "needs_revision",
            Self::Cancelled => "cancelled",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "queued" => Self::Queued,
            "in_progress" => Self::InProgress,
            "passed" => Self::Passed,
            "failed" => Self::Failed,
            "needs_revision" => Self::NeedsRevision,
            "cancelled" => Self::Cancelled,
            _ => Self::Queued,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FeatureStatus {
    Pending,
    InProgress,
    Completed,
    Failed,
}

impl FeatureStatus {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Pending => "pending",
            Self::InProgress => "in_progress",
            Self::Completed => "completed",
            Self::Failed => "failed",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "pending" => Self::Pending,
            "in_progress" => Self::InProgress,
            "completed" => Self::Completed,
            "failed" => Self::Failed,
            _ => Self::Pending,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ReviewVerdict {
    Pass,
    NeedsRevision,
    Fail,
}

impl ReviewVerdict {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Pass => "pass",
            Self::NeedsRevision => "needsRevision",
            Self::Fail => "fail",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "pass" => Self::Pass,
            "needsRevision" | "needs_revision" => Self::NeedsRevision,
            "fail" => Self::Fail,
            _ => Self::Fail,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LogLevel {
    Debug,
    Info,
    Warning,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DeployEnvironment {
    Development,
    Staging,
    Production,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DeployStatus {
    Pending,
    InProgress,
    Success,
    Failed,
    RolledBack,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AssetType {
    Image,
    Video,
    Audio,
    Design,
    Document,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AssetStatus {
    Generated,
    Reviewed,
    Approved,
    Rejected,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PublicationStatus {
    Scheduled,
    Publishing,
    Published,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ChannelType {
    Medium,
    Wordpress,
    Twitter,
    Linkedin,
    DevTo,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ExportFormat {
    Markdown,
    Html,
    Plaintext,
    Pdf,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PromptSource {
    User,
    Community,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PromptOutcome {
    Completed,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BackendType {
    Claude,
    Codex,
    Gemini,
    Ollama,
    LmStudio,
    LlamaCpp,
    Mlx,
    OpenCode,
}

impl BackendType {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Claude => "claude",
            Self::Codex => "codex",
            Self::Gemini => "gemini",
            Self::Ollama => "ollama",
            Self::LmStudio => "lmStudio",
            Self::LlamaCpp => "llamaCpp",
            Self::Mlx => "mlx",
            Self::OpenCode => "opencode",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "claude" => Self::Claude,
            "codex" => Self::Codex,
            "gemini" => Self::Gemini,
            "ollama" => Self::Ollama,
            "lmStudio" | "lm_studio" => Self::LmStudio,
            "llamaCpp" | "llama_cpp" => Self::LlamaCpp,
            "mlx" => Self::Mlx,
            "opencode" | "open_code" => Self::OpenCode,
            _ => Self::Claude,
        }
    }
}

// ─── Model Structs ───────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Project {
    pub id: String,
    pub name: String,
    pub description: String,
    pub tech_stack: String,
    pub status: String,
    pub directory_path: String,
    pub project_type: String,
    pub telegram_chat_id: Option<i64>,
    pub staging_pr_number: Option<i32>,
    pub completed_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

impl Project {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            name: row.get("name")?,
            description: row.get("description")?,
            tech_stack: row.get("techStack")?,
            status: row.get("status")?,
            directory_path: row.get("directoryPath")?,
            project_type: row.get("projectType")?,
            telegram_chat_id: row.get("telegramChatId")?,
            staging_pr_number: row.get("stagingPrNumber")?,
            completed_at: row.get("completedAt")?,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }

    pub fn all(conn: &Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT * FROM project ORDER BY updatedAt DESC"
        )?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn get(conn: &Connection, id: &str) -> rusqlite::Result<Self> {
        conn.query_row(
            "SELECT * FROM project WHERE id = ?1",
            [id],
            |row| Self::from_row(row),
        )
    }

    pub fn insert(conn: &Connection, project: &Self) -> rusqlite::Result<()> {
        conn.execute(
            "INSERT INTO project (id, name, description, techStack, status, directoryPath, projectType, telegramChatId, completedAt, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![
                project.id, project.name, project.description, project.tech_stack,
                project.status, project.directory_path, project.project_type,
                project.telegram_chat_id, project.completed_at, project.created_at, project.updated_at,
            ],
        )?;
        Ok(())
    }

    pub fn update(conn: &Connection, project: &Self) -> rusqlite::Result<()> {
        conn.execute(
            "UPDATE project SET name=?2, description=?3, techStack=?4, status=?5,
             directoryPath=?6, projectType=?7, telegramChatId=?8, completedAt=?9, updatedAt=datetime('now')
             WHERE id=?1",
            params![
                project.id, project.name, project.description, project.tech_stack,
                project.status, project.directory_path, project.project_type,
                project.telegram_chat_id, project.completed_at,
            ],
        )?;
        Ok(())
    }

    pub fn delete(conn: &Connection, id: &str) -> rusqlite::Result<()> {
        conn.execute("DELETE FROM project WHERE id = ?1", [id])?;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Feature {
    pub id: String,
    pub project_id: String,
    pub name: String,
    pub description: String,
    pub priority: i32,
    pub status: String,
    pub integration_pr_number: Option<i32>,
    pub created_at: String,
    pub updated_at: String,
}

impl Feature {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            project_id: row.get("projectId")?,
            name: row.get("name")?,
            description: row.get("description")?,
            priority: row.get("priority")?,
            status: row.get("status")?,
            integration_pr_number: row.get("integrationPrNumber")?,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentTask {
    pub id: String,
    pub project_id: String,
    pub feature_id: Option<String>,
    pub agent_type: String,
    pub title: String,
    pub description: String,
    pub priority: i32,
    pub status: String,
    pub result: Option<String>,
    pub error_message: Option<String>,
    pub retry_count: i32,
    pub max_retries: i32,
    pub session_id: Option<String>,
    pub branch_name: Option<String>,
    pub pr_number: Option<i32>,
    pub cost_usd: Option<f64>,
    pub duration_ms: Option<i64>,
    pub created_at: String,
    pub updated_at: String,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
    pub backend: Option<String>,
    pub prompt_chain_id: Option<String>,
    pub revision_prompt: Option<String>,
    pub skill_persona: Option<String>,
    pub archived_at: Option<String>,
}

impl AgentTask {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            project_id: row.get("projectId")?,
            feature_id: row.get("featureId")?,
            agent_type: row.get("agentType")?,
            title: row.get("title")?,
            description: row.get("description")?,
            priority: row.get("priority")?,
            status: row.get("status")?,
            result: row.get("result")?,
            error_message: row.get("errorMessage")?,
            retry_count: row.get("retryCount")?,
            max_retries: row.get("maxRetries")?,
            session_id: row.get("sessionId")?,
            branch_name: row.get("branchName")?,
            pr_number: row.get("prNumber")?,
            cost_usd: row.get("costUSD")?,
            duration_ms: row.get("durationMs")?,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
            started_at: row.get("startedAt")?,
            completed_at: row.get("completedAt")?,
            backend: row.get("backend")?,
            prompt_chain_id: row.get("promptChainId")?,
            revision_prompt: row.get("revisionPrompt")?,
            skill_persona: row.get("skillPersona")?,
            archived_at: row.get("archivedAt")?,
        })
    }

    pub fn all_for_project(conn: &Connection, project_id: &str) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT * FROM agentTask WHERE projectId = ?1 ORDER BY priority DESC, createdAt ASC"
        )?;
        let rows = stmt.query_map([project_id], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn get(conn: &Connection, id: &str) -> rusqlite::Result<Self> {
        conn.query_row("SELECT * FROM agentTask WHERE id = ?1", [id], |row| Self::from_row(row))
    }

    pub fn insert(conn: &Connection, task: &Self) -> rusqlite::Result<()> {
        conn.execute(
            "INSERT INTO agentTask (id, projectId, featureId, agentType, title, description, priority, status, retryCount, maxRetries, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
            params![
                task.id, task.project_id, task.feature_id, task.agent_type,
                task.title, task.description, task.priority, task.status,
                task.retry_count, task.max_retries, task.created_at, task.updated_at,
            ],
        )?;
        Ok(())
    }

    pub fn update_status(conn: &Connection, id: &str, status: &str) -> rusqlite::Result<()> {
        conn.execute(
            "UPDATE agentTask SET status = ?2, updatedAt = datetime('now') WHERE id = ?1",
            params![id, status],
        )?;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskDependency {
    pub task_id: String,
    pub depends_on_task_id: String,
}

impl TaskDependency {
    pub fn for_task(conn: &Connection, task_id: &str) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT taskId, dependsOnTaskId FROM taskDependency WHERE taskId = ?1"
        )?;
        let rows = stmt.query_map([task_id], |row| {
            Ok(Self {
                task_id: row.get(0)?,
                depends_on_task_id: row.get(1)?,
            })
        })?;
        rows.collect()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Review {
    pub id: String,
    pub task_id: String,
    pub score: f64,
    pub verdict: String,
    pub summary: String,
    pub issues: Option<String>,
    pub suggestions: Option<String>,
    pub security_notes: Option<String>,
    pub session_id: Option<String>,
    pub cost_usd: Option<f64>,
    pub is_approved: bool,
    pub created_at: String,
}

impl Review {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            task_id: row.get("taskId")?,
            score: row.get("score")?,
            verdict: row.get("verdict")?,
            summary: row.get("summary")?,
            issues: row.get("issues")?,
            suggestions: row.get("suggestions")?,
            security_notes: row.get("securityNotes")?,
            session_id: row.get("sessionId")?,
            cost_usd: row.get("costUSD")?,
            is_approved: row.get::<_, i32>("isApproved")? != 0,
            created_at: row.get("createdAt")?,
        })
    }

    pub fn all(conn: &Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM review ORDER BY createdAt DESC")?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn approve(conn: &Connection, id: &str) -> rusqlite::Result<()> {
        conn.execute("UPDATE review SET isApproved = 1 WHERE id = ?1", [id])?;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentLog {
    pub id: String,
    pub task_id: String,
    pub agent_type: String,
    pub level: String,
    pub message: String,
    pub metadata: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Deployment {
    pub id: String,
    pub project_id: String,
    pub environment: String,
    pub status: String,
    pub version: String,
    pub commit_hash: Option<String>,
    pub deployed_by: String,
    pub rollback_from: Option<String>,
    pub logs: Option<String>,
    pub deploy_method: Option<String>,
    pub port: Option<i32>,
    pub container_id: Option<String>,
    pub process_id: Option<i32>,
    pub fix_task_id: Option<String>,
    pub auto_fix_attempts: i32,
    pub created_at: String,
    pub completed_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CostTracking {
    pub id: String,
    pub project_id: String,
    pub task_id: Option<String>,
    pub agent_type: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cost_usd: f64,
    pub model: String,
    pub session_id: Option<String>,
    pub backend: Option<String>,
    pub created_at: String,
}

impl CostTracking {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            project_id: row.get("projectId")?,
            task_id: row.get("taskId")?,
            agent_type: row.get("agentType")?,
            input_tokens: row.get("inputTokens")?,
            output_tokens: row.get("outputTokens")?,
            cost_usd: row.get("costUSD")?,
            model: row.get("model")?,
            session_id: row.get("sessionId")?,
            backend: row.get("backend")?,
            created_at: row.get("createdAt")?,
        })
    }

    pub fn summary(conn: &Connection) -> rusqlite::Result<CostSummary> {
        let total_cost: f64 = conn.query_row(
            "SELECT COALESCE(SUM(costUSD), 0.0) FROM costTracking", [], |row| row.get(0)
        )?;
        let total_tasks: i32 = conn.query_row(
            "SELECT COUNT(*) FROM costTracking", [], |row| row.get(0)
        )?;
        let total_tokens: i64 = conn.query_row(
            "SELECT COALESCE(SUM(inputTokens + outputTokens), 0) FROM costTracking", [], |row| row.get(0)
        )?;
        Ok(CostSummary { total_cost, total_tasks, total_tokens })
    }

    pub fn by_project(conn: &Connection, project_id: &str) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT * FROM costTracking WHERE projectId = ?1 ORDER BY createdAt DESC"
        )?;
        let rows = stmt.query_map([project_id], |row| Self::from_row(row))?;
        rows.collect()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CostSummary {
    pub total_cost: f64,
    pub total_tasks: i32,
    pub total_tokens: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MCPServerConfig {
    pub id: String,
    pub name: String,
    pub command: String,
    pub arguments: String,
    pub environment_vars: String,
    pub is_enabled: bool,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Prompt {
    pub id: String,
    pub title: String,
    pub content: String,
    pub source: String,
    pub category: String,
    pub contributor: Option<String>,
    pub is_built_in: bool,
    pub is_favorite: bool,
    pub version: i32,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptVersion {
    pub id: String,
    pub prompt_id: String,
    pub version: i32,
    pub title: String,
    pub content: String,
    pub change_note: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptChain {
    pub id: String,
    pub name: String,
    pub description: String,
    pub category: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptChainStep {
    pub id: String,
    pub chain_id: String,
    pub prompt_id: String,
    pub step_order: i32,
    pub transition_note: Option<String>,
    pub condition: Option<String>,
    pub on_fail_step_order: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptTag {
    pub prompt_id: String,
    pub tag: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptUsage {
    pub id: String,
    pub prompt_id: String,
    pub project_id: Option<String>,
    pub task_id: Option<String>,
    pub chain_id: Option<String>,
    pub agent_type: Option<String>,
    pub outcome: Option<String>,
    pub review_score: Option<f64>,
    pub used_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedAsset {
    pub id: String,
    pub project_id: String,
    pub task_id: String,
    pub agent_type: String,
    pub asset_type: String,
    pub name: String,
    pub description: String,
    pub file_path: String,
    pub mime_type: Option<String>,
    pub file_size: Option<i64>,
    pub source_url: Option<String>,
    pub metadata: Option<String>,
    pub status: String,
    pub review_task_id: Option<String>,
    pub version: i32,
    pub thumbnail_path: Option<String>,
    pub checksum: Option<String>,
    pub parent_asset_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

impl GeneratedAsset {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            project_id: row.get("projectId")?,
            task_id: row.get("taskId")?,
            agent_type: row.get("agentType")?,
            asset_type: row.get("assetType")?,
            name: row.get("name")?,
            description: row.get("description")?,
            file_path: row.get("filePath")?,
            mime_type: row.get("mimeType")?,
            file_size: row.get("fileSize")?,
            source_url: row.get("sourceUrl")?,
            metadata: row.get("metadata")?,
            status: row.get("status")?,
            review_task_id: row.get("reviewTaskId")?,
            version: row.get("version")?,
            thumbnail_path: row.get("thumbnailPath")?,
            checksum: row.get("checksum")?,
            parent_asset_id: row.get("parentAssetId")?,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }

    pub fn for_project(conn: &Connection, project_id: &str) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT * FROM generatedAsset WHERE projectId = ?1 ORDER BY createdAt DESC"
        )?;
        let rows = stmt.query_map([project_id], |row| Self::from_row(row))?;
        rows.collect()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Publication {
    pub id: String,
    pub asset_id: String,
    pub project_id: String,
    pub channel_id: String,
    pub status: String,
    pub external_id: Option<String>,
    pub published_url: Option<String>,
    pub scheduled_at: Option<String>,
    pub published_at: Option<String>,
    pub error_message: Option<String>,
    pub export_format: String,
    pub created_at: String,
    pub updated_at: String,
}

impl Publication {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            asset_id: row.get("assetId")?,
            project_id: row.get("projectId")?,
            channel_id: row.get("channelId")?,
            status: row.get("status")?,
            external_id: row.get("externalId")?,
            published_url: row.get("publishedUrl")?,
            scheduled_at: row.get("scheduledAt")?,
            published_at: row.get("publishedAt")?,
            error_message: row.get("errorMessage")?,
            export_format: row.get("exportFormat")?,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }

    pub fn all(conn: &Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM publication ORDER BY createdAt DESC")?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublishingChannel {
    pub id: String,
    pub name: String,
    pub channel_type: String,
    pub credentials_json: String,
    pub is_enabled: bool,
    pub default_tags: String,
    pub created_at: String,
    pub updated_at: String,
}

impl PublishingChannel {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            name: row.get("name")?,
            channel_type: row.get("channelType")?,
            credentials_json: row.get("credentialsJSON")?,
            is_enabled: row.get::<_, i32>("isEnabled")? != 0,
            default_tags: row.get("defaultTags")?,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }

    pub fn all(conn: &Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM publishingChannel ORDER BY name")?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }
}

// ─── Notification & Health Enums ─────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum NotificationCategory {
    BackendHealth,
    McpHealth,
    RateLimit,
    Task,
    Deploy,
    Budget,
    System,
}

impl NotificationCategory {
    pub fn as_str(&self) -> &str {
        match self {
            Self::BackendHealth => "backendHealth",
            Self::McpHealth => "mcpHealth",
            Self::RateLimit => "rateLimit",
            Self::Task => "task",
            Self::Deploy => "deploy",
            Self::Budget => "budget",
            Self::System => "system",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "backendHealth" | "backend_health" => Self::BackendHealth,
            "mcpHealth" | "mcp_health" => Self::McpHealth,
            "rateLimit" | "rate_limit" => Self::RateLimit,
            "task" => Self::Task,
            "deploy" => Self::Deploy,
            "budget" => Self::Budget,
            _ => Self::System,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum NotificationSeverity {
    Info,
    Warning,
    Error,
    Success,
}

impl NotificationSeverity {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Info => "info",
            Self::Warning => "warning",
            Self::Error => "error",
            Self::Success => "success",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "warning" => Self::Warning,
            "error" => Self::Error,
            "success" => Self::Success,
            _ => Self::Info,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum HealthTargetType {
    Backend,
    Mcp,
}

impl HealthTargetType {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Backend => "backend",
            Self::Mcp => "mcp",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "mcp" => Self::Mcp,
            _ => Self::Backend,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum HealthStatus {
    Healthy,
    Degraded,
    Unhealthy,
    Unknown,
}

impl HealthStatus {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Healthy => "healthy",
            Self::Degraded => "degraded",
            Self::Unhealthy => "unhealthy",
            Self::Unknown => "unknown",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "healthy" => Self::Healthy,
            "degraded" => Self::Degraded,
            "unhealthy" => Self::Unhealthy,
            _ => Self::Unknown,
        }
    }
}

// ─── AppNotification Model ──────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppNotification {
    pub id: String,
    pub category: String,
    pub severity: String,
    pub title: String,
    pub message: String,
    pub metadata: Option<String>,
    pub is_read: bool,
    pub is_dismissed: bool,
    pub created_at: String,
}

impl AppNotification {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            category: row.get("category")?,
            severity: row.get("severity")?,
            title: row.get("title")?,
            message: row.get("message")?,
            metadata: row.get("metadata")?,
            is_read: row.get::<_, i32>("isRead")? != 0,
            is_dismissed: row.get::<_, i32>("isDismissed")? != 0,
            created_at: row.get("createdAt")?,
        })
    }

    pub fn recent(conn: &Connection, limit: i32) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT * FROM appNotification WHERE isDismissed = 0 ORDER BY createdAt DESC LIMIT ?1"
        )?;
        let rows = stmt.query_map([limit], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn unread_count(conn: &Connection) -> rusqlite::Result<i32> {
        conn.query_row(
            "SELECT COUNT(*) FROM appNotification WHERE isRead = 0 AND isDismissed = 0",
            [],
            |row| row.get(0),
        )
    }

    pub fn insert(conn: &Connection, notif: &Self) -> rusqlite::Result<()> {
        conn.execute(
            "INSERT INTO appNotification (id, category, severity, title, message, metadata, isRead, isDismissed, createdAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                notif.id, notif.category, notif.severity, notif.title, notif.message,
                notif.metadata, notif.is_read as i32, notif.is_dismissed as i32, notif.created_at,
            ],
        )?;
        Ok(())
    }

    pub fn mark_read(conn: &Connection, id: &str) -> rusqlite::Result<()> {
        conn.execute("UPDATE appNotification SET isRead = 1 WHERE id = ?1", [id])?;
        Ok(())
    }

    pub fn mark_all_read(conn: &Connection) -> rusqlite::Result<()> {
        conn.execute_batch("UPDATE appNotification SET isRead = 1 WHERE isRead = 0")?;
        Ok(())
    }

    pub fn dismiss(conn: &Connection, id: &str) -> rusqlite::Result<()> {
        conn.execute("UPDATE appNotification SET isDismissed = 1 WHERE id = ?1", [id])?;
        Ok(())
    }

    pub fn delete_one(conn: &Connection, id: &str) -> rusqlite::Result<()> {
        conn.execute("DELETE FROM appNotification WHERE id = ?1", [id])?;
        Ok(())
    }

    pub fn clear_all(conn: &Connection) -> rusqlite::Result<()> {
        conn.execute_batch("DELETE FROM appNotification")?;
        Ok(())
    }

    pub fn prune_old(conn: &Connection, days: i32) -> rusqlite::Result<()> {
        conn.execute(
            "DELETE FROM appNotification WHERE createdAt < datetime('now', ?1)",
            [format!("-{} days", days)],
        )?;
        Ok(())
    }
}

// ─── HealthEvent Model ──────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HealthEvent {
    pub id: String,
    pub target_type: String,
    pub target_name: String,
    pub status: String,
    pub response_time_ms: Option<i32>,
    pub error_message: Option<String>,
    pub metadata: Option<String>,
    pub checked_at: String,
}

impl HealthEvent {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            target_type: row.get("targetType")?,
            target_name: row.get("targetName")?,
            status: row.get("status")?,
            response_time_ms: row.get("responseTimeMs")?,
            error_message: row.get("errorMessage")?,
            metadata: row.get("metadata")?,
            checked_at: row.get("checkedAt")?,
        })
    }

    pub fn insert(conn: &Connection, event: &Self) -> rusqlite::Result<()> {
        conn.execute(
            "INSERT INTO healthEvent (id, targetType, targetName, status, responseTimeMs, errorMessage, metadata, checkedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                event.id, event.target_type, event.target_name, event.status,
                event.response_time_ms, event.error_message, event.metadata, event.checked_at,
            ],
        )?;
        Ok(())
    }

    pub fn latest_by_target_type(conn: &Connection, target_type: &str) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT h.* FROM healthEvent h
             INNER JOIN (
                 SELECT targetName, MAX(checkedAt) as maxCheckedAt
                 FROM healthEvent WHERE targetType = ?1
                 GROUP BY targetName
             ) latest ON h.targetName = latest.targetName AND h.checkedAt = latest.maxCheckedAt
             WHERE h.targetType = ?1"
        )?;
        let rows = stmt.query_map([target_type], |row| Self::from_row(row))?;
        rows.collect()
    }
}

// ─── Settings (stored in a simple key-value table or app config) ─────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub projects_dir: String,
    pub max_concurrency: i32,
    pub monthly_budget_usd: f64,
    pub claude_enabled: bool,
    pub codex_enabled: bool,
    pub gemini_enabled: bool,
    pub ollama_enabled: bool,
    pub lm_studio_enabled: bool,
    pub llama_cpp_enabled: bool,
    pub mlx_enabled: bool,
    pub opencode_enabled: bool,
    pub telegram_bot_token: Option<String>,
    pub telegram_chat_id: Option<String>,
    #[serde(default)]
    pub slack_webhook_url: Option<String>,
    pub has_completed_setup: bool,
    pub agent_backend_overrides: Option<AgentBackendOverrides>,
    #[serde(default)]
    pub webhook_enabled: Option<bool>,
    #[serde(default)]
    pub webhook_port: Option<u16>,
    #[serde(default)]
    pub webhook_api_key: Option<String>,
    #[serde(default)]
    pub webhook_github_secret: Option<String>,
    #[serde(default)]
    pub language: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentBackendOverrides {
    pub analyzer: Option<String>,
    pub coder: Option<String>,
    pub reviewer: Option<String>,
    pub tester: Option<String>,
    pub devops: Option<String>,
    pub monitor: Option<String>,
    pub content_writer: Option<String>,
    pub designer: Option<String>,
    pub image_generator: Option<String>,
    pub video_editor: Option<String>,
    pub publisher: Option<String>,
    pub planner: Option<String>,
}

impl Default for AppSettings {
    fn default() -> Self {
        let projects_dir = dirs::home_dir()
            .unwrap_or_default()
            .join("CreedFlow")
            .join("projects")
            .to_string_lossy()
            .to_string();
        Self {
            projects_dir,
            max_concurrency: 3,
            monthly_budget_usd: 50.0,
            claude_enabled: true,
            codex_enabled: true,
            gemini_enabled: true,
            ollama_enabled: false,
            lm_studio_enabled: false,
            llama_cpp_enabled: false,
            mlx_enabled: false,
            opencode_enabled: false,
            telegram_bot_token: None,
            telegram_chat_id: None,
            slack_webhook_url: None,
            has_completed_setup: false,
            agent_backend_overrides: None,
            webhook_enabled: None,
            webhook_port: None,
            webhook_api_key: None,
            webhook_github_secret: None,
            language: None,
        }
    }
}

// ─── Chat Attachment ────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatAttachment {
    pub name: String,
    pub path: String,
    pub is_image: bool,
}

// ─── Project Chat Messages ──────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectMessage {
    pub id: String,
    pub project_id: String,
    pub role: String,
    pub content: String,
    pub backend: Option<String>,
    pub cost_usd: Option<f64>,
    pub duration_ms: Option<i64>,
    pub metadata: Option<String>,
    pub attachments: Option<String>,
    pub created_at: String,
}

impl ProjectMessage {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            project_id: row.get("project_id")?,
            role: row.get("role")?,
            content: row.get("content")?,
            backend: row.get("backend")?,
            cost_usd: row.get("cost_usd")?,
            duration_ms: row.get("duration_ms")?,
            metadata: row.get("metadata")?,
            attachments: row.get("attachments")?,
            created_at: row.get("created_at")?,
        })
    }

    pub fn insert(conn: &Connection, msg: &ProjectMessage) -> rusqlite::Result<()> {
        conn.execute(
            "INSERT INTO project_message (id, project_id, role, content, backend, cost_usd, duration_ms, metadata, attachments, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                msg.id,
                msg.project_id,
                msg.role,
                msg.content,
                msg.backend,
                msg.cost_usd,
                msg.duration_ms,
                msg.metadata,
                msg.attachments,
                msg.created_at,
            ],
        )?;
        Ok(())
    }

    pub fn list_by_project(conn: &Connection, project_id: &str) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT * FROM project_message WHERE project_id = ?1 ORDER BY created_at ASC"
        )?;
        let rows = stmt.query_map(params![project_id], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn update_metadata(conn: &Connection, id: &str, metadata: &str) -> rusqlite::Result<()> {
        conn.execute(
            "UPDATE project_message SET metadata = ?1 WHERE id = ?2",
            params![metadata, id],
        )?;
        Ok(())
    }
}

// ─── Task Comments ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskComment {
    pub id: String,
    pub task_id: String,
    pub content: String,
    pub author: String,
    pub created_at: String,
}

impl TaskComment {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            task_id: row.get("taskId")?,
            content: row.get("content")?,
            author: row.get("author")?,
            created_at: row.get("createdAt")?,
        })
    }

    pub fn insert(conn: &Connection, comment: &Self) -> rusqlite::Result<()> {
        conn.execute(
            "INSERT INTO taskComment (id, taskId, content, author, createdAt)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                comment.id, comment.task_id, comment.content,
                comment.author, comment.created_at,
            ],
        )?;
        Ok(())
    }

    pub fn all_for_task(conn: &Connection, task_id: &str) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT * FROM taskComment WHERE taskId = ?1 ORDER BY createdAt ASC"
        )?;
        let rows = stmt.query_map([task_id], |row| Self::from_row(row))?;
        rows.collect()
    }
}

// ─── Prompt Usage (read-only for task prompt history) ───────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptUsageRecord {
    pub id: String,
    pub prompt_id: String,
    pub prompt_title: Option<String>,
    pub project_id: Option<String>,
    pub task_id: Option<String>,
    pub chain_id: Option<String>,
    pub agent_type: Option<String>,
    pub outcome: Option<String>,
    pub review_score: Option<f64>,
    pub used_at: String,
}

impl PromptUsageRecord {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            prompt_id: row.get("promptId")?,
            prompt_title: row.get("promptTitle")?,
            project_id: row.get("projectId")?,
            task_id: row.get("taskId")?,
            chain_id: row.get("chainId")?,
            agent_type: row.get("agentType")?,
            outcome: row.get("outcome")?,
            review_score: row.get("reviewScore")?,
            used_at: row.get("usedAt")?,
        })
    }

    pub fn for_task(conn: &Connection, task_id: &str) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT pu.*, p.title AS promptTitle
             FROM promptUsage pu
             LEFT JOIN prompt p ON p.id = pu.promptId
             WHERE pu.taskId = ?1
             ORDER BY pu.usedAt DESC"
        )?;
        let rows = stmt.query_map([task_id], |row| Self::from_row(row))?;
        rows.collect()
    }
}

// ─── Project Time Stats ─────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectTimeStats {
    pub elapsed_ms: i64,
    pub total_work_ms: i64,
    pub idle_ms: i64,
    pub agent_breakdown: Vec<AgentTimeStat>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentTimeStat {
    pub agent_type: String,
    pub total_ms: i64,
    pub task_count: i64,
}

// ─── Project Template ───────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectTemplate {
    pub id: String,
    pub name: String,
    pub description: String,
    pub icon: String,
    pub tech_stack: String,
    pub project_type: String,
    pub features: Vec<TemplateFeature>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TemplateFeature {
    pub name: String,
    pub description: String,
    pub tasks: Vec<TemplateTask>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TemplateTask {
    pub agent_type: String,
    pub title: String,
    pub description: String,
    pub priority: i32,
}

// ─── Backend Scoring & Cost Budgets ──────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackendScore {
    pub id: String,
    pub backend_type: String,
    pub cost_efficiency: f64,
    pub speed: f64,
    pub reliability: f64,
    pub quality: f64,
    pub composite_score: f64,
    pub sample_size: i32,
    pub updated_at: String,
}

impl BackendScore {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            backend_type: row.get("backendType")?,
            cost_efficiency: row.get("costEfficiency")?,
            speed: row.get("speed")?,
            reliability: row.get("reliability")?,
            quality: row.get("quality")?,
            composite_score: row.get("compositeScore")?,
            sample_size: row.get("sampleSize")?,
            updated_at: row.get("updatedAt")?,
        })
    }

    pub fn all(conn: &Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM backendScore ORDER BY compositeScore DESC")?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn by_type(conn: &Connection, backend_type: &str) -> rusqlite::Result<Option<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM backendScore WHERE backendType = ?1")?;
        let mut rows = stmt.query_map([backend_type], |row| Self::from_row(row))?;
        match rows.next() {
            Some(Ok(score)) => Ok(Some(score)),
            Some(Err(e)) => Err(e),
            None => Ok(None),
        }
    }

    pub fn upsert(conn: &Connection, score: &BackendScore) -> rusqlite::Result<()> {
        conn.execute(
            "INSERT INTO backendScore (id, backendType, costEfficiency, speed, reliability, quality, compositeScore, sampleSize, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(backendType) DO UPDATE SET
                costEfficiency = excluded.costEfficiency,
                speed = excluded.speed,
                reliability = excluded.reliability,
                quality = excluded.quality,
                compositeScore = excluded.compositeScore,
                sampleSize = excluded.sampleSize,
                updatedAt = excluded.updatedAt",
            params![
                score.id, score.backend_type, score.cost_efficiency, score.speed,
                score.reliability, score.quality, score.composite_score,
                score.sample_size, score.updated_at
            ],
        )?;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CostBudget {
    pub id: String,
    pub scope: String,
    pub project_id: Option<String>,
    pub period: String,
    pub limit_usd: f64,
    pub warn_threshold: f64,
    pub critical_threshold: f64,
    pub pause_on_exceed: bool,
    pub is_enabled: bool,
    pub created_at: String,
    pub updated_at: String,
}

impl CostBudget {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            scope: row.get("scope")?,
            project_id: row.get("projectId")?,
            period: row.get("period")?,
            limit_usd: row.get("limitUsd")?,
            warn_threshold: row.get("warnThreshold")?,
            critical_threshold: row.get("criticalThreshold")?,
            pause_on_exceed: row.get::<_, i32>("pauseOnExceed")? != 0,
            is_enabled: row.get::<_, i32>("isEnabled")? != 0,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }

    pub fn all_enabled(conn: &Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM costBudget WHERE isEnabled = 1 ORDER BY createdAt DESC")?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn all(conn: &Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM costBudget ORDER BY createdAt DESC")?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn insert(conn: &Connection, budget: &CostBudget) -> rusqlite::Result<()> {
        conn.execute(
            "INSERT INTO costBudget (id, scope, projectId, period, limitUsd, warnThreshold, criticalThreshold, pauseOnExceed, isEnabled, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![
                budget.id, budget.scope, budget.project_id, budget.period,
                budget.limit_usd, budget.warn_threshold, budget.critical_threshold,
                budget.pause_on_exceed as i32, budget.is_enabled as i32,
                budget.created_at, budget.updated_at
            ],
        )?;
        Ok(())
    }

    pub fn update(conn: &Connection, budget: &CostBudget) -> rusqlite::Result<()> {
        conn.execute(
            "UPDATE costBudget SET scope = ?2, projectId = ?3, period = ?4, limitUsd = ?5,
             warnThreshold = ?6, criticalThreshold = ?7, pauseOnExceed = ?8, isEnabled = ?9,
             updatedAt = ?10 WHERE id = ?1",
            params![
                budget.id, budget.scope, budget.project_id, budget.period,
                budget.limit_usd, budget.warn_threshold, budget.critical_threshold,
                budget.pause_on_exceed as i32, budget.is_enabled as i32,
                budget.updated_at
            ],
        )?;
        Ok(())
    }

    pub fn delete(conn: &Connection, id: &str) -> rusqlite::Result<()> {
        conn.execute("DELETE FROM costBudget WHERE id = ?1", [id])?;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BudgetAlert {
    pub id: String,
    pub budget_id: String,
    pub threshold_type: String,
    pub current_spend: f64,
    pub limit_usd: f64,
    pub percentage: f64,
    pub acknowledged_at: Option<String>,
    pub created_at: String,
}

impl BudgetAlert {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            budget_id: row.get("budgetId")?,
            threshold_type: row.get("thresholdType")?,
            current_spend: row.get("currentSpend")?,
            limit_usd: row.get("limitUsd")?,
            percentage: row.get("percentage")?,
            acknowledged_at: row.get("acknowledgedAt")?,
            created_at: row.get("createdAt")?,
        })
    }

    pub fn by_budget(conn: &Connection, budget_id: &str) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT * FROM budgetAlert WHERE budgetId = ?1 ORDER BY createdAt DESC"
        )?;
        let rows = stmt.query_map([budget_id], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn recent(conn: &Connection, limit: i32) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare(
            "SELECT * FROM budgetAlert ORDER BY createdAt DESC LIMIT ?1"
        )?;
        let rows = stmt.query_map([limit], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn acknowledge(conn: &Connection, id: &str) -> rusqlite::Result<()> {
        conn.execute(
            "UPDATE budgetAlert SET acknowledgedAt = datetime('now') WHERE id = ?1",
            [id],
        )?;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BudgetUtilization {
    pub budget: CostBudget,
    pub current_spend: f64,
    pub percentage: f64,
    pub alerts: Vec<BudgetAlert>,
}

// ─── Agent Persona ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentPersona {
    pub id: String,
    pub name: String,
    pub description: String,
    pub system_prompt: String,
    pub agent_types: Vec<String>,
    pub tags: Vec<String>,
    pub is_built_in: bool,
    pub is_enabled: bool,
    pub created_at: String,
    pub updated_at: String,
}

impl AgentPersona {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        let agent_types_json: String = row.get("agentTypes")?;
        let tags_json: String = row.get("tags")?;
        Ok(Self {
            id: row.get("id")?,
            name: row.get("name")?,
            description: row.get("description")?,
            system_prompt: row.get("systemPrompt")?,
            agent_types: serde_json::from_str(&agent_types_json).unwrap_or_default(),
            tags: serde_json::from_str(&tags_json).unwrap_or_default(),
            is_built_in: row.get::<_, i32>("isBuiltIn")? != 0,
            is_enabled: row.get::<_, i32>("isEnabled")? != 0,
            created_at: row.get("createdAt")?,
            updated_at: row.get("updatedAt")?,
        })
    }

    pub fn all(conn: &Connection) -> rusqlite::Result<Vec<Self>> {
        let mut stmt = conn.prepare("SELECT * FROM agentPersona ORDER BY name")?;
        let rows = stmt.query_map([], |row| Self::from_row(row))?;
        rows.collect()
    }

    pub fn insert(conn: &Connection, persona: &AgentPersona) -> rusqlite::Result<()> {
        let agent_types_json = serde_json::to_string(&persona.agent_types).unwrap_or_else(|_| "[]".to_string());
        let tags_json = serde_json::to_string(&persona.tags).unwrap_or_else(|_| "[]".to_string());
        conn.execute(
            "INSERT INTO agentPersona (id, name, description, systemPrompt, agentTypes, tags, isBuiltIn, isEnabled, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                persona.id, persona.name, persona.description, persona.system_prompt,
                agent_types_json, tags_json,
                persona.is_built_in as i32, persona.is_enabled as i32,
                persona.created_at, persona.updated_at
            ],
        )?;
        Ok(())
    }

    pub fn update(conn: &Connection, persona: &AgentPersona) -> rusqlite::Result<()> {
        let agent_types_json = serde_json::to_string(&persona.agent_types).unwrap_or_else(|_| "[]".to_string());
        let tags_json = serde_json::to_string(&persona.tags).unwrap_or_else(|_| "[]".to_string());
        conn.execute(
            "UPDATE agentPersona SET name = ?2, description = ?3, systemPrompt = ?4,
             agentTypes = ?5, tags = ?6, isEnabled = ?7, updatedAt = ?8 WHERE id = ?1",
            params![
                persona.id, persona.name, persona.description, persona.system_prompt,
                agent_types_json, tags_json,
                persona.is_enabled as i32, persona.updated_at
            ],
        )?;
        Ok(())
    }

    pub fn delete(conn: &Connection, id: &str) -> rusqlite::Result<()> {
        conn.execute("DELETE FROM agentPersona WHERE id = ?1 AND isBuiltIn = 0", [id])?;
        Ok(())
    }
}
