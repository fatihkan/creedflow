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
        (19, V19_PROJECT_MESSAGE),
        (20, V20_MESSAGE_ATTACHMENTS),
        (21, V21_NOTIFICATIONS_AND_HEALTH),
        (22, V22_PROJECT_COMPLETION_AND_COMMENTS),
        (23, V23_BACKEND_SCORING_AND_BUDGETS),
        (24, V24_AGENT_PERSONAS),
        (25, V25_CHAIN_CONDITIONS),
        (26, V26_ISSUE_TRACKING),
        (27, V27_AUTOMATION_FLOWS),
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

const V19_PROJECT_MESSAGE: &str = r#"
CREATE TABLE IF NOT EXISTS project_message (
    id TEXT PRIMARY KEY NOT NULL,
    project_id TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    backend TEXT,
    cost_usd REAL,
    duration_ms INTEGER,
    metadata TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_project_message_project_created ON project_message(project_id, created_at);
"#;

const V20_MESSAGE_ATTACHMENTS: &str = r#"
ALTER TABLE project_message ADD COLUMN attachments TEXT;
"#;

const V21_NOTIFICATIONS_AND_HEALTH: &str = r#"
CREATE TABLE IF NOT EXISTS appNotification (
    id TEXT PRIMARY KEY NOT NULL,
    category TEXT NOT NULL DEFAULT 'system',
    severity TEXT NOT NULL DEFAULT 'info',
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    metadata TEXT,
    isRead INTEGER NOT NULL DEFAULT 0,
    isDismissed INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_appNotification_isRead ON appNotification(isRead);
CREATE INDEX IF NOT EXISTS idx_appNotification_category ON appNotification(category);
CREATE INDEX IF NOT EXISTS idx_appNotification_createdAt ON appNotification(createdAt);

CREATE TABLE IF NOT EXISTS healthEvent (
    id TEXT PRIMARY KEY NOT NULL,
    targetType TEXT NOT NULL,
    targetName TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'unknown',
    responseTimeMs INTEGER,
    errorMessage TEXT,
    metadata TEXT,
    checkedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_healthEvent_targetType_name ON healthEvent(targetType, targetName);
CREATE INDEX IF NOT EXISTS idx_healthEvent_checkedAt ON healthEvent(checkedAt);
"#;

const V22_PROJECT_COMPLETION_AND_COMMENTS: &str = r#"
ALTER TABLE project ADD COLUMN completedAt TEXT;

CREATE TABLE IF NOT EXISTS taskComment (
    id TEXT PRIMARY KEY NOT NULL,
    taskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    author TEXT NOT NULL DEFAULT 'user',
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_taskComment_taskId ON taskComment(taskId);
"#;

const V23_BACKEND_SCORING_AND_BUDGETS: &str = r#"
CREATE TABLE IF NOT EXISTS backendScore (
    id TEXT PRIMARY KEY NOT NULL,
    backendType TEXT NOT NULL,
    costEfficiency REAL NOT NULL DEFAULT 0.5,
    speed REAL NOT NULL DEFAULT 0.5,
    reliability REAL NOT NULL DEFAULT 0.5,
    quality REAL NOT NULL DEFAULT 0.5,
    compositeScore REAL NOT NULL DEFAULT 0.5,
    sampleSize INTEGER NOT NULL DEFAULT 0,
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_backendScore_type ON backendScore(backendType);

CREATE TABLE IF NOT EXISTS costBudget (
    id TEXT PRIMARY KEY NOT NULL,
    scope TEXT NOT NULL DEFAULT 'global',
    projectId TEXT REFERENCES project(id) ON DELETE CASCADE,
    period TEXT NOT NULL DEFAULT 'monthly',
    limitUsd REAL NOT NULL DEFAULT 50.0,
    warnThreshold REAL NOT NULL DEFAULT 0.80,
    criticalThreshold REAL NOT NULL DEFAULT 0.95,
    pauseOnExceed INTEGER NOT NULL DEFAULT 0,
    isEnabled INTEGER NOT NULL DEFAULT 1,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_costBudget_scope ON costBudget(scope);

CREATE TABLE IF NOT EXISTS budgetAlert (
    id TEXT PRIMARY KEY NOT NULL,
    budgetId TEXT NOT NULL REFERENCES costBudget(id) ON DELETE CASCADE,
    thresholdType TEXT NOT NULL,
    currentSpend REAL NOT NULL,
    limitUsd REAL NOT NULL,
    percentage REAL NOT NULL,
    acknowledgedAt TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_budgetAlert_budgetId ON budgetAlert(budgetId);
"#;

const V24_AGENT_PERSONAS: &str = r#"
CREATE TABLE IF NOT EXISTS agentPersona (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    systemPrompt TEXT NOT NULL,
    agentTypes TEXT NOT NULL DEFAULT '[]',
    tags TEXT NOT NULL DEFAULT '[]',
    isBuiltIn INTEGER NOT NULL DEFAULT 0,
    isEnabled INTEGER NOT NULL DEFAULT 1,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_agentPersona_name ON agentPersona(name);

INSERT OR IGNORE INTO agentPersona (id, name, description, systemPrompt, agentTypes, tags, isBuiltIn, isEnabled, createdAt, updatedAt)
VALUES (lower(hex(randomblob(16))), 'Senior Architect', 'Focuses on clean architecture, SOLID principles, and scalability', 'You are a senior software architect with 15+ years of experience. Prioritize clean architecture, SOLID principles, design patterns, and scalability. Always consider maintainability and separation of concerns.', '["analyzer","coder","reviewer"]', '["architecture","design"]', 1, 1, datetime('now'), datetime('now'));

INSERT OR IGNORE INTO agentPersona (id, name, description, systemPrompt, agentTypes, tags, isBuiltIn, isEnabled, createdAt, updatedAt)
VALUES (lower(hex(randomblob(16))), 'Security Expert', 'Emphasizes security best practices and vulnerability prevention', 'You are a cybersecurity expert. Prioritize OWASP top 10 prevention, input validation, authentication/authorization best practices, and secure coding patterns. Flag any potential vulnerabilities.', '["coder","reviewer","tester"]', '["security","audit"]', 1, 1, datetime('now'), datetime('now'));

INSERT OR IGNORE INTO agentPersona (id, name, description, systemPrompt, agentTypes, tags, isBuiltIn, isEnabled, createdAt, updatedAt)
VALUES (lower(hex(randomblob(16))), 'Performance Engineer', 'Optimizes for speed, memory efficiency, and scalability', 'You are a performance engineering specialist. Focus on algorithmic efficiency, memory optimization, caching strategies, lazy loading, and profiling. Minimize unnecessary allocations and I/O operations.', '["coder","reviewer","tester"]', '["performance","optimization"]', 1, 1, datetime('now'), datetime('now'));

INSERT OR IGNORE INTO agentPersona (id, name, description, systemPrompt, agentTypes, tags, isBuiltIn, isEnabled, createdAt, updatedAt)
VALUES (lower(hex(randomblob(16))), 'TDD Practitioner', 'Test-driven development with comprehensive test coverage', 'You are a TDD advocate. Write tests before implementation. Ensure comprehensive unit, integration, and edge-case coverage. Use mocks and stubs appropriately. Aim for >90% coverage.', '["coder","tester"]', '["testing","tdd"]', 1, 1, datetime('now'), datetime('now'));

INSERT OR IGNORE INTO agentPersona (id, name, description, systemPrompt, agentTypes, tags, isBuiltIn, isEnabled, createdAt, updatedAt)
VALUES (lower(hex(randomblob(16))), 'Technical Writer', 'Clear documentation, API docs, and user guides', 'You are a technical documentation specialist. Write clear, concise documentation with examples. Follow docs-as-code principles. Include API references, usage examples, and troubleshooting guides.', '["contentWriter","analyzer"]', '["documentation","writing"]', 1, 1, datetime('now'), datetime('now'));
"#;

const V25_CHAIN_CONDITIONS: &str = r#"
ALTER TABLE promptChainStep ADD COLUMN condition TEXT;
ALTER TABLE promptChainStep ADD COLUMN onFailStepOrder INTEGER;
"#;

const V26_ISSUE_TRACKING: &str = r#"
CREATE TABLE IF NOT EXISTS issueTrackingConfig (
    id TEXT PRIMARY KEY NOT NULL,
    projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    name TEXT NOT NULL,
    credentialsJSON TEXT NOT NULL DEFAULT '{}',
    configJSON TEXT NOT NULL DEFAULT '{}',
    isEnabled INTEGER NOT NULL DEFAULT 1,
    syncBackEnabled INTEGER NOT NULL DEFAULT 0,
    lastSyncAt TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_issueTrackingConfig_projectId ON issueTrackingConfig(projectId);

CREATE TABLE IF NOT EXISTS issueMapping (
    id TEXT PRIMARY KEY NOT NULL,
    configId TEXT NOT NULL REFERENCES issueTrackingConfig(id) ON DELETE CASCADE,
    taskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
    externalIssueId TEXT NOT NULL,
    externalIdentifier TEXT NOT NULL,
    externalUrl TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'imported',
    lastSyncedAt TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_issueMapping_configId ON issueMapping(configId);
CREATE INDEX IF NOT EXISTS idx_issueMapping_taskId ON issueMapping(taskId);
CREATE UNIQUE INDEX IF NOT EXISTS idx_issueMapping_config_issue ON issueMapping(configId, externalIssueId);
"#;

const V27_AUTOMATION_FLOWS: &str = r#"
CREATE TABLE IF NOT EXISTS automationFlow (
    id TEXT PRIMARY KEY NOT NULL,
    projectId TEXT REFERENCES project(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    triggerType TEXT NOT NULL,
    triggerConfig TEXT NOT NULL DEFAULT '{}',
    actionType TEXT NOT NULL,
    actionConfig TEXT NOT NULL DEFAULT '{}',
    isEnabled INTEGER NOT NULL DEFAULT 1,
    lastTriggeredAt TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_automationFlow_projectId ON automationFlow(projectId);
CREATE INDEX IF NOT EXISTS idx_automationFlow_triggerType ON automationFlow(triggerType);
"#;
