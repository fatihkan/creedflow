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
    General,
}

impl ProjectType {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Software => "software",
            Self::Content => "content",
            Self::Image => "image",
            Self::Video => "video",
            Self::General => "general",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "software" => Self::Software,
            "content" => Self::Content,
            "image" => Self::Image,
            "video" => Self::Video,
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
            _ => Self::Analyzer,
        }
    }

    pub fn all() -> Vec<Self> {
        vec![
            Self::Analyzer, Self::Coder, Self::Reviewer, Self::Tester,
            Self::Devops, Self::Monitor, Self::ContentWriter, Self::Designer,
            Self::ImageGenerator, Self::VideoEditor, Self::Publisher,
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
            "INSERT INTO project (id, name, description, techStack, status, directoryPath, projectType, telegramChatId, createdAt, updatedAt)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                project.id, project.name, project.description, project.tech_stack,
                project.status, project.directory_path, project.project_type,
                project.telegram_chat_id, project.created_at, project.updated_at,
            ],
        )?;
        Ok(())
    }

    pub fn update(conn: &Connection, project: &Self) -> rusqlite::Result<()> {
        conn.execute(
            "UPDATE project SET name=?2, description=?3, techStack=?4, status=?5,
             directoryPath=?6, projectType=?7, telegramChatId=?8, updatedAt=datetime('now')
             WHERE id=?1",
            params![
                project.id, project.name, project.description, project.tech_stack,
                project.status, project.directory_path, project.project_type,
                project.telegram_chat_id,
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
    pub telegram_bot_token: Option<String>,
    pub telegram_chat_id: Option<String>,
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
            telegram_bot_token: None,
            telegram_chat_id: None,
        }
    }
}
