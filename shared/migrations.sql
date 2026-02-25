-- CreedFlow Shared SQLite Schema
-- Both macOS (Swift/GRDB) and Desktop (Rust/rusqlite) apps implement these migrations.
-- This file is the reference schema. SQLite files are interchangeable between apps.

-- ═══════════════════════════════════════════════════════════════════
-- Migration v1: Core tables
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE project (
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

CREATE TABLE feature (
    id TEXT PRIMARY KEY NOT NULL,
    projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending',
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE agentTask (
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

CREATE TABLE taskDependency (
    taskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
    dependsOnTaskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
    PRIMARY KEY (taskId, dependsOnTaskId)
);

CREATE TABLE review (
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

CREATE TABLE agentLog (
    id TEXT PRIMARY KEY NOT NULL,
    taskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
    agentType TEXT NOT NULL,
    level TEXT NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    metadata TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE deployment (
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

CREATE TABLE costTracking (
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

CREATE INDEX idx_agentTask_status_priority ON agentTask(status, priority);
CREATE INDEX idx_agentTask_projectId ON agentTask(projectId);
CREATE INDEX idx_costTracking_projectId ON costTracking(projectId);
CREATE INDEX idx_agentLog_taskId ON agentLog(taskId);

-- ═══════════════════════════════════════════════════════════════════
-- Migration v2: MCP Server Config
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE mcpServerConfig (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE,
    command TEXT NOT NULL,
    arguments TEXT NOT NULL DEFAULT '[]',
    environmentVars TEXT NOT NULL DEFAULT '{}',
    isEnabled INTEGER NOT NULL DEFAULT 1,
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ═══════════════════════════════════════════════════════════════════
-- Migration v3: Prompt Library
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE prompt (
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

CREATE INDEX idx_prompt_source_category ON prompt(source, category);

-- ═══════════════════════════════════════════════════════════════════
-- Migration v4: Review approval + indices
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE review ADD COLUMN isApproved INTEGER NOT NULL DEFAULT 0;
CREATE INDEX idx_review_taskId ON review(taskId);
CREATE INDEX idx_review_isApproved ON review(isApproved);
CREATE INDEX idx_deployment_projectId ON deployment(projectId);
CREATE INDEX idx_costTracking_createdAt ON costTracking(createdAt);
CREATE INDEX idx_agentTask_status ON agentTask(status);
CREATE INDEX idx_feature_projectId ON feature(projectId);

-- ═══════════════════════════════════════════════════════════════════
-- Migration v5: Deployment runtime fields
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE deployment ADD COLUMN deployMethod TEXT;
ALTER TABLE deployment ADD COLUMN port INTEGER;
ALTER TABLE deployment ADD COLUMN containerId TEXT;
ALTER TABLE deployment ADD COLUMN processId INTEGER;

-- ═══════════════════════════════════════════════════════════════════
-- Migration v6: Project type
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE project ADD COLUMN projectType TEXT NOT NULL DEFAULT 'software';

-- ═══════════════════════════════════════════════════════════════════
-- Migration v7: Backend tracking
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE agentTask ADD COLUMN backend TEXT;
ALTER TABLE costTracking ADD COLUMN backend TEXT;

-- ═══════════════════════════════════════════════════════════════════
-- Migration v8: Advanced prompts (versioning, chaining, tagging, usage)
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE prompt ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

CREATE TABLE promptVersion (
    id TEXT PRIMARY KEY NOT NULL,
    promptId TEXT NOT NULL REFERENCES prompt(id) ON DELETE CASCADE,
    version INTEGER NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    changeNote TEXT,
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE promptChain (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT '',
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE promptChainStep (
    id TEXT PRIMARY KEY NOT NULL,
    chainId TEXT NOT NULL REFERENCES promptChain(id) ON DELETE CASCADE,
    promptId TEXT NOT NULL REFERENCES prompt(id) ON DELETE CASCADE,
    stepOrder INTEGER NOT NULL,
    transitionNote TEXT
);

CREATE TABLE promptTag (
    promptId TEXT NOT NULL REFERENCES prompt(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    PRIMARY KEY (promptId, tag)
);

CREATE TABLE promptUsage (
    id TEXT PRIMARY KEY NOT NULL,
    promptId TEXT NOT NULL REFERENCES prompt(id) ON DELETE CASCADE,
    projectId TEXT,
    taskId TEXT,
    outcome TEXT,
    reviewScore REAL,
    usedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_promptVersion_promptId_version ON promptVersion(promptId, version);
CREATE INDEX idx_promptChainStep_chainId_order ON promptChainStep(chainId, stepOrder);
CREATE INDEX idx_promptTag_tag ON promptTag(tag);
CREATE INDEX idx_promptUsage_promptId ON promptUsage(promptId);

-- ═══════════════════════════════════════════════════════════════════
-- Migration v9: Chain usage tracking
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE promptUsage ADD COLUMN chainId TEXT;
CREATE INDEX idx_promptUsage_chainId ON promptUsage(chainId);

-- ═══════════════════════════════════════════════════════════════════
-- Migration v10: Prompt agent + chain task
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE promptUsage ADD COLUMN agentType TEXT;
ALTER TABLE agentTask ADD COLUMN promptChainId TEXT;
CREATE INDEX idx_promptUsage_agentType ON promptUsage(agentType);

-- ═══════════════════════════════════════════════════════════════════
-- Migration v11: Generated assets
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE generatedAsset (
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

CREATE INDEX idx_generatedAsset_projectId ON generatedAsset(projectId);
CREATE INDEX idx_generatedAsset_taskId ON generatedAsset(taskId);
CREATE INDEX idx_generatedAsset_status ON generatedAsset(status);

-- ═══════════════════════════════════════════════════════════════════
-- Migration v12: Asset versioning
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE generatedAsset ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE generatedAsset ADD COLUMN thumbnailPath TEXT;
ALTER TABLE generatedAsset ADD COLUMN checksum TEXT;
ALTER TABLE generatedAsset ADD COLUMN parentAssetId TEXT REFERENCES generatedAsset(id);
CREATE INDEX idx_generatedAsset_parentAssetId ON generatedAsset(parentAssetId);

-- ═══════════════════════════════════════════════════════════════════
-- Migration v13: Publishing
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE publishingChannel (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    channelType TEXT NOT NULL,
    credentialsJSON TEXT NOT NULL DEFAULT '{}',
    isEnabled INTEGER NOT NULL DEFAULT 1,
    defaultTags TEXT NOT NULL DEFAULT '',
    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE publication (
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

CREATE INDEX idx_publication_assetId ON publication(assetId);
CREATE INDEX idx_publication_projectId ON publication(projectId);
CREATE INDEX idx_publication_status ON publication(status);
