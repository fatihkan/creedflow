use rusqlite::Connection;

/// All 13 migrations matching the Swift/GRDB schema exactly.
/// Migration SQL is idempotent via the creedflow_migrations tracking table.
pub fn run_all(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS creedflow_migrations (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL DEFAULT (datetime('now'))
        );"
    )?;

    let applied: Vec<i32> = {
        let mut stmt = conn.prepare("SELECT version FROM creedflow_migrations ORDER BY version")?;
        let result = stmt.query_map([], |row| row.get(0))?
            .filter_map(|r| r.ok())
            .collect();
        result
    };

    let migrations: Vec<(i32, &str)> = vec![
        (1, V1_CREATE_TABLES),
        (2, V2_MCP_SERVER_CONFIG),
        (3, V3_PROMPT),
        (4, V4_REVIEW_APPROVAL_AND_INDICES),
        (5, V5_DEPLOYMENT_RUNTIME),
        (6, V6_PROJECT_TYPE),
        (7, V7_BACKEND_TRACKING),
        (8, V8_ADVANCED_PROMPTS),
        (9, V9_CHAIN_USAGE_TRACKING),
        (10, V10_PROMPT_AGENT_AND_CHAIN_TASK),
        (11, V11_GENERATED_ASSETS),
        (12, V12_ASSET_VERSIONING),
        (13, V13_PUBLISHING),
        (14, V14_DEPLOYMENT_AUTO_FIX),
        (15, V15_REVISION_PROMPT),
        (16, V16_GIT_BRANCHING),
        (17, V17_SKILL_PERSONA),
        (18, V18_TASK_ARCHIVE),
    ];

    for (version, sql) in migrations {
        if !applied.contains(&version) {
            // Run each statement individually so that "duplicate column"
            // errors (from a DB already migrated by Swift/GRDB) don't
            // prevent subsequent statements in the same migration from
            // executing.
            for statement in sql.split(';') {
                let stmt = statement.trim();
                if stmt.is_empty() {
                    continue;
                }
                match conn.execute_batch(stmt) {
                    Ok(()) => {}
                    Err(e) => {
                        let msg = e.to_string();
                        if msg.contains("duplicate column name") || msg.contains("already exists") {
                            log::warn!("Migration v{}: skipping already-applied statement", version);
                        } else {
                            return Err(e);
                        }
                    }
                }
            }
            conn.execute(
                "INSERT INTO creedflow_migrations (version) VALUES (?1)",
                [version],
            )?;
            log::info!("Applied migration v{}", version);
        }
    }

    Ok(())
}

const V1_CREATE_TABLES: &str = r#"
CREATE TABLE IF NOT EXISTS project (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    techStack TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'planning',
    directoryPath TEXT NOT NULL DEFAULT '',
    telegramChatId INTEGER,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS feature (
    id TEXT PRIMARY KEY NOT NULL,
    projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending',
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS agentTask (
    id TEXT PRIMARY KEY NOT NULL,
    projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    featureId TEXT REFERENCES feature(id) ON DELETE SET NULL,
    agentType TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'queued',
    result TEXT,
    errorMessage TEXT,
    retryCount INTEGER NOT NULL DEFAULT 0,
    maxRetries INTEGER NOT NULL DEFAULT 3,
    sessionId TEXT,
    branchName TEXT,
    prNumber INTEGER,
    costUSD REAL,
    durationMs INTEGER,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now')),
    startedAt TEXT,
    completedAt TEXT
);

CREATE TABLE IF NOT EXISTS taskDependency (
    taskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
    dependsOnTaskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
    PRIMARY KEY (taskId, dependsOnTaskId)
);

CREATE TABLE IF NOT EXISTS review (
    id TEXT PRIMARY KEY NOT NULL,
    taskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
    score REAL NOT NULL DEFAULT 0.0,
    verdict TEXT NOT NULL DEFAULT 'fail',
    summary TEXT NOT NULL DEFAULT '',
    issues TEXT,
    suggestions TEXT,
    securityNotes TEXT,
    sessionId TEXT,
    costUSD REAL,
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS agentLog (
    id TEXT PRIMARY KEY NOT NULL,
    taskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
    agentType TEXT NOT NULL,
    level TEXT NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    metadata TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS deployment (
    id TEXT PRIMARY KEY NOT NULL,
    projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    environment TEXT NOT NULL DEFAULT 'staging',
    status TEXT NOT NULL DEFAULT 'pending',
    version TEXT NOT NULL DEFAULT '',
    commitHash TEXT,
    deployedBy TEXT NOT NULL DEFAULT '',
    rollbackFrom TEXT,
    logs TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    completedAt TEXT
);

CREATE TABLE IF NOT EXISTS costTracking (
    id TEXT PRIMARY KEY NOT NULL,
    projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    taskId TEXT,
    agentType TEXT NOT NULL,
    inputTokens INTEGER NOT NULL DEFAULT 0,
    outputTokens INTEGER NOT NULL DEFAULT 0,
    costUSD REAL NOT NULL DEFAULT 0.0,
    model TEXT NOT NULL DEFAULT '',
    sessionId TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_agentTask_status_priority ON agentTask(status, priority);
CREATE INDEX IF NOT EXISTS idx_agentTask_projectId ON agentTask(projectId);
CREATE INDEX IF NOT EXISTS idx_costTracking_projectId ON costTracking(projectId);
CREATE INDEX IF NOT EXISTS idx_agentLog_taskId ON agentLog(taskId);
"#;

const V2_MCP_SERVER_CONFIG: &str = r#"
CREATE TABLE IF NOT EXISTS mcpServerConfig (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE,
    command TEXT NOT NULL,
    arguments TEXT NOT NULL DEFAULT '[]',
    environmentVars TEXT NOT NULL DEFAULT '{}',
    isEnabled INTEGER NOT NULL DEFAULT 1,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);
"#;

const V3_PROMPT: &str = r#"
CREATE TABLE IF NOT EXISTS prompt (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'user',
    category TEXT NOT NULL DEFAULT '',
    contributor TEXT,
    isBuiltIn INTEGER NOT NULL DEFAULT 0,
    isFavorite INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_prompt_source_category ON prompt(source, category);
"#;

const V4_REVIEW_APPROVAL_AND_INDICES: &str = r#"
ALTER TABLE review ADD COLUMN isApproved INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_review_taskId ON review(taskId);
CREATE INDEX IF NOT EXISTS idx_review_isApproved ON review(isApproved);
CREATE INDEX IF NOT EXISTS idx_deployment_projectId ON deployment(projectId);
CREATE INDEX IF NOT EXISTS idx_costTracking_createdAt ON costTracking(createdAt);
CREATE INDEX IF NOT EXISTS idx_agentTask_status ON agentTask(status);
CREATE INDEX IF NOT EXISTS idx_feature_projectId ON feature(projectId);
"#;

const V5_DEPLOYMENT_RUNTIME: &str = r#"
ALTER TABLE deployment ADD COLUMN deployMethod TEXT;
ALTER TABLE deployment ADD COLUMN port INTEGER;
ALTER TABLE deployment ADD COLUMN containerId TEXT;
ALTER TABLE deployment ADD COLUMN processId INTEGER;
"#;

const V6_PROJECT_TYPE: &str = r#"
ALTER TABLE project ADD COLUMN projectType TEXT NOT NULL DEFAULT 'software';
"#;

const V7_BACKEND_TRACKING: &str = r#"
ALTER TABLE agentTask ADD COLUMN backend TEXT;
ALTER TABLE costTracking ADD COLUMN backend TEXT;
"#;

const V8_ADVANCED_PROMPTS: &str = r#"
ALTER TABLE prompt ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS promptVersion (
    id TEXT PRIMARY KEY NOT NULL,
    promptId TEXT NOT NULL REFERENCES prompt(id) ON DELETE CASCADE,
    version INTEGER NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    changeNote TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS promptChain (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT '',
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS promptChainStep (
    id TEXT PRIMARY KEY NOT NULL,
    chainId TEXT NOT NULL REFERENCES promptChain(id) ON DELETE CASCADE,
    promptId TEXT NOT NULL REFERENCES prompt(id) ON DELETE CASCADE,
    stepOrder INTEGER NOT NULL,
    transitionNote TEXT
);

CREATE TABLE IF NOT EXISTS promptTag (
    promptId TEXT NOT NULL REFERENCES prompt(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    PRIMARY KEY (promptId, tag)
);

CREATE TABLE IF NOT EXISTS promptUsage (
    id TEXT PRIMARY KEY NOT NULL,
    promptId TEXT NOT NULL REFERENCES prompt(id) ON DELETE CASCADE,
    projectId TEXT,
    taskId TEXT,
    outcome TEXT,
    reviewScore REAL,
    usedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_promptVersion_promptId_version ON promptVersion(promptId, version);
CREATE INDEX IF NOT EXISTS idx_promptChainStep_chainId_order ON promptChainStep(chainId, stepOrder);
CREATE INDEX IF NOT EXISTS idx_promptTag_tag ON promptTag(tag);
CREATE INDEX IF NOT EXISTS idx_promptUsage_promptId ON promptUsage(promptId);
"#;

const V9_CHAIN_USAGE_TRACKING: &str = r#"
ALTER TABLE promptUsage ADD COLUMN chainId TEXT;

CREATE INDEX IF NOT EXISTS idx_promptUsage_chainId ON promptUsage(chainId);
"#;

const V10_PROMPT_AGENT_AND_CHAIN_TASK: &str = r#"
ALTER TABLE promptUsage ADD COLUMN agentType TEXT;
ALTER TABLE agentTask ADD COLUMN promptChainId TEXT;

CREATE INDEX IF NOT EXISTS idx_promptUsage_agentType ON promptUsage(agentType);
"#;

const V11_GENERATED_ASSETS: &str = r#"
CREATE TABLE IF NOT EXISTS generatedAsset (
    id TEXT PRIMARY KEY NOT NULL,
    projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    taskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
    agentType TEXT NOT NULL,
    assetType TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    filePath TEXT NOT NULL,
    mimeType TEXT,
    fileSize INTEGER,
    sourceUrl TEXT,
    metadata TEXT,
    status TEXT NOT NULL DEFAULT 'generated',
    reviewTaskId TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_generatedAsset_projectId ON generatedAsset(projectId);
CREATE INDEX IF NOT EXISTS idx_generatedAsset_taskId ON generatedAsset(taskId);
CREATE INDEX IF NOT EXISTS idx_generatedAsset_status ON generatedAsset(status);
"#;

const V12_ASSET_VERSIONING: &str = r#"
ALTER TABLE generatedAsset ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE generatedAsset ADD COLUMN thumbnailPath TEXT;
ALTER TABLE generatedAsset ADD COLUMN checksum TEXT;
ALTER TABLE generatedAsset ADD COLUMN parentAssetId TEXT REFERENCES generatedAsset(id);

CREATE INDEX IF NOT EXISTS idx_generatedAsset_parentAssetId ON generatedAsset(parentAssetId);
"#;

const V13_PUBLISHING: &str = r#"
CREATE TABLE IF NOT EXISTS publishingChannel (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    channelType TEXT NOT NULL,
    credentialsJSON TEXT NOT NULL DEFAULT '{}',
    isEnabled INTEGER NOT NULL DEFAULT 1,
    defaultTags TEXT NOT NULL DEFAULT '',
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS publication (
    id TEXT PRIMARY KEY NOT NULL,
    assetId TEXT NOT NULL REFERENCES generatedAsset(id) ON DELETE CASCADE,
    projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    channelId TEXT NOT NULL REFERENCES publishingChannel(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'scheduled',
    externalId TEXT,
    publishedUrl TEXT,
    scheduledAt TEXT,
    publishedAt TEXT,
    errorMessage TEXT,
    exportFormat TEXT NOT NULL DEFAULT 'markdown',
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_publication_assetId ON publication(assetId);
CREATE INDEX IF NOT EXISTS idx_publication_projectId ON publication(projectId);
CREATE INDEX IF NOT EXISTS idx_publication_status ON publication(status);
"#;

const V14_DEPLOYMENT_AUTO_FIX: &str = r#"
ALTER TABLE deployment ADD COLUMN fixTaskId TEXT;
ALTER TABLE deployment ADD COLUMN autoFixAttempts INTEGER NOT NULL DEFAULT 0;
"#;

const V15_REVISION_PROMPT: &str = r#"
ALTER TABLE agentTask ADD COLUMN revisionPrompt TEXT;
"#;

const V16_GIT_BRANCHING: &str = r#"
ALTER TABLE feature ADD COLUMN integrationPrNumber INTEGER;
ALTER TABLE project ADD COLUMN stagingPrNumber INTEGER;
"#;

const V17_SKILL_PERSONA: &str = r#"
ALTER TABLE agentTask ADD COLUMN skillPersona TEXT;
"#;

const V18_TASK_ARCHIVE: &str = r#"
ALTER TABLE agentTask ADD COLUMN archivedAt TEXT;
CREATE INDEX IF NOT EXISTS idx_agentTask_archivedAt ON agentTask(archivedAt);
"#;
