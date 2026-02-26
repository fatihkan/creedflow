import Foundation
import GRDB
import os.log

/// The application database — manages SQLite connection, migrations, and provides
/// a shared `DatabaseQueue` for all read/write operations.
public struct AppDatabase {
    public let dbQueue: DatabaseQueue

    init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_create_tables") { db in
            // Projects
            try db.create(table: "project") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("description", .text).notNull()
                t.column("techStack", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull().defaults(to: "planning")
                t.column("directoryPath", .text).notNull().defaults(to: "")
                t.column("telegramChatId", .integer)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Features
            try db.create(table: "feature") { t in
                t.primaryKey("id", .text).notNull()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("description", .text).notNull()
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Agent Tasks
            try db.create(table: "agentTask") { t in
                t.primaryKey("id", .text).notNull()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("featureId", .text)
                    .references("feature", onDelete: .setNull)
                t.column("agentType", .text).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text).notNull()
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull().defaults(to: "queued")
                t.column("result", .text)
                t.column("errorMessage", .text)
                t.column("retryCount", .integer).notNull().defaults(to: 0)
                t.column("maxRetries", .integer).notNull().defaults(to: 3)
                t.column("sessionId", .text)
                t.column("branchName", .text)
                t.column("prNumber", .integer)
                t.column("costUSD", .double)
                t.column("durationMs", .integer)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("completedAt", .datetime)
            }

            // Task Dependencies (junction table)
            try db.create(table: "taskDependency") { t in
                t.column("taskId", .text).notNull()
                    .references("agentTask", onDelete: .cascade)
                t.column("dependsOnTaskId", .text).notNull()
                    .references("agentTask", onDelete: .cascade)
                t.primaryKey(["taskId", "dependsOnTaskId"])
            }

            // Reviews
            try db.create(table: "review") { t in
                t.primaryKey("id", .text).notNull()
                t.column("taskId", .text).notNull()
                    .references("agentTask", onDelete: .cascade)
                t.column("score", .double).notNull()
                t.column("verdict", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("issues", .text)
                t.column("suggestions", .text)
                t.column("securityNotes", .text)
                t.column("sessionId", .text)
                t.column("costUSD", .double)
                t.column("createdAt", .datetime).notNull()
            }

            // Agent Logs
            try db.create(table: "agentLog") { t in
                t.primaryKey("id", .text).notNull()
                t.column("taskId", .text).notNull()
                    .references("agentTask", onDelete: .cascade)
                t.column("agentType", .text).notNull()
                t.column("level", .text).notNull().defaults(to: "info")
                t.column("message", .text).notNull()
                t.column("metadata", .text)
                t.column("createdAt", .datetime).notNull()
            }

            // Deployments
            try db.create(table: "deployment") { t in
                t.primaryKey("id", .text).notNull()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("environment", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("version", .text).notNull()
                t.column("commitHash", .text)
                t.column("deployedBy", .text).notNull().defaults(to: "system")
                t.column("rollbackFrom", .text)
                t.column("logs", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)
            }

            // Cost Tracking
            try db.create(table: "costTracking") { t in
                t.primaryKey("id", .text).notNull()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("taskId", .text)
                    .references("agentTask", onDelete: .setNull)
                t.column("agentType", .text).notNull()
                t.column("inputTokens", .integer).notNull().defaults(to: 0)
                t.column("outputTokens", .integer).notNull().defaults(to: 0)
                t.column("costUSD", .double).notNull().defaults(to: 0)
                t.column("model", .text).notNull()
                t.column("sessionId", .text)
                t.column("createdAt", .datetime).notNull()
            }

            // Indexes
            try db.create(
                index: "agentTask_on_status_priority",
                on: "agentTask",
                columns: ["status", "priority"]
            )
            try db.create(
                index: "agentTask_on_projectId",
                on: "agentTask",
                columns: ["projectId"]
            )
            try db.create(
                index: "agentLog_on_taskId",
                on: "agentLog",
                columns: ["taskId"]
            )
            try db.create(
                index: "costTracking_on_projectId",
                on: "costTracking",
                columns: ["projectId"]
            )
        }

        migrator.registerMigration("v2_mcp_server_config") { db in
            try db.create(table: "mcpServerConfig") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull().unique()
                t.column("command", .text).notNull()
                t.column("arguments", .text).notNull().defaults(to: "[]")
                t.column("environmentVars", .text).notNull().defaults(to: "{}")
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v3_prompt") { db in
            try db.create(table: "prompt") { t in
                t.primaryKey("id", .text).notNull()
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("source", .text).notNull().defaults(to: "user")
                t.column("category", .text).notNull().defaults(to: "general")
                t.column("contributor", .text)
                t.column("isBuiltIn", .boolean).notNull().defaults(to: false)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "prompt_on_source_category",
                on: "prompt",
                columns: ["source", "category"]
            )
        }

        migrator.registerMigration("v4_review_approval_and_indices") { db in
            // #29: Add isApproved column to reviews
            try db.alter(table: "review") { t in
                t.add(column: "isApproved", .boolean).notNull().defaults(to: false)
            }

            // #36: Missing indices on frequently queried columns
            try db.create(index: "review_on_taskId", on: "review", columns: ["taskId"])
            try db.create(index: "review_on_isApproved", on: "review", columns: ["isApproved"])
            try db.create(index: "deployment_on_projectId", on: "deployment", columns: ["projectId"])
            try db.create(index: "costTracking_on_createdAt", on: "costTracking", columns: ["createdAt"])
            try db.create(index: "agentTask_on_status", on: "agentTask", columns: ["status"])
            try db.create(index: "feature_on_projectId", on: "feature", columns: ["projectId"])
        }

        migrator.registerMigration("v5_deployment_runtime") { db in
            try db.alter(table: "deployment") { t in
                t.add(column: "deployMethod", .text)
                t.add(column: "port", .integer)
                t.add(column: "containerId", .text)
                t.add(column: "processId", .integer)
            }
        }

        migrator.registerMigration("v6_project_type") { db in
            try db.alter(table: "project") { t in
                t.add(column: "projectType", .text).notNull().defaults(to: "software")
            }
        }

        migrator.registerMigration("v7_backend_tracking") { db in
            try db.alter(table: "agentTask") { t in
                t.add(column: "backend", .text)
            }
            try db.alter(table: "costTracking") { t in
                t.add(column: "backend", .text)
            }
        }

        migrator.registerMigration("v8_advanced_prompts") { db in
            // Add version tracking to prompts
            try db.alter(table: "prompt") { t in
                t.add(column: "version", .integer).notNull().defaults(to: 1)
            }

            // Prompt version history
            try db.create(table: "promptVersion") { t in
                t.primaryKey("id", .text).notNull()
                t.column("promptId", .text).notNull()
                    .references("prompt", onDelete: .cascade)
                t.column("version", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("changeNote", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(
                index: "promptVersion_on_promptId_version",
                on: "promptVersion",
                columns: ["promptId", "version"],
                unique: true
            )

            // Prompt chains
            try db.create(table: "promptChain") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("category", .text).notNull().defaults(to: "general")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Prompt chain steps (junction)
            try db.create(table: "promptChainStep") { t in
                t.primaryKey("id", .text).notNull()
                t.column("chainId", .text).notNull()
                    .references("promptChain", onDelete: .cascade)
                t.column("promptId", .text).notNull()
                    .references("prompt", onDelete: .cascade)
                t.column("stepOrder", .integer).notNull()
                t.column("transitionNote", .text)
            }
            try db.create(
                index: "promptChainStep_on_chainId_stepOrder",
                on: "promptChainStep",
                columns: ["chainId", "stepOrder"],
                unique: true
            )

            // Prompt tags (junction)
            try db.create(table: "promptTag") { t in
                t.column("promptId", .text).notNull()
                    .references("prompt", onDelete: .cascade)
                t.column("tag", .text).notNull()
                t.primaryKey(["promptId", "tag"])
            }
            try db.create(index: "promptTag_on_tag", on: "promptTag", columns: ["tag"])

            // Prompt usage tracking
            try db.create(table: "promptUsage") { t in
                t.primaryKey("id", .text).notNull()
                t.column("promptId", .text).notNull()
                    .references("prompt", onDelete: .cascade)
                t.column("projectId", .text)
                    .references("project", onDelete: .setNull)
                t.column("taskId", .text)
                    .references("agentTask", onDelete: .setNull)
                t.column("outcome", .text)
                t.column("reviewScore", .double)
                t.column("usedAt", .datetime).notNull()
            }
            try db.create(index: "promptUsage_on_promptId", on: "promptUsage", columns: ["promptId"])
        }

        migrator.registerMigration("v9_chain_usage_tracking") { db in
            try db.alter(table: "promptUsage") { t in
                t.add(column: "chainId", .text).references("promptChain", onDelete: .setNull)
            }
            try db.create(index: "promptUsage_on_chainId", on: "promptUsage", columns: ["chainId"])
        }

        migrator.registerMigration("v10_prompt_agent_and_chain_task") { db in
            // Track which agent type used a prompt (for effectiveness-based recommendation)
            try db.alter(table: "promptUsage") { t in
                t.add(column: "agentType", .text)
            }
            try db.create(index: "promptUsage_on_agentType", on: "promptUsage", columns: ["agentType"])

            // Link tasks to prompt chains for step-by-step execution
            try db.alter(table: "agentTask") { t in
                t.add(column: "promptChainId", .text).references("promptChain", onDelete: .setNull)
            }
        }

        migrator.registerMigration("v11_generated_assets") { db in
            try db.create(table: "generatedAsset") { t in
                t.primaryKey("id", .text).notNull()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("taskId", .text).notNull()
                    .references("agentTask", onDelete: .cascade)
                t.column("agentType", .text).notNull()
                t.column("assetType", .text).notNull()
                t.column("name", .text).notNull()
                t.column("assetDescription", .text).notNull().defaults(to: "")
                t.column("filePath", .text).notNull()
                t.column("mimeType", .text)
                t.column("fileSize", .integer)
                t.column("sourceUrl", .text)
                t.column("metadata", .text)
                t.column("status", .text).notNull().defaults(to: "generated")
                t.column("reviewTaskId", .text)
                    .references("agentTask", onDelete: .setNull)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "generatedAsset_on_projectId", on: "generatedAsset", columns: ["projectId"])
            try db.create(index: "generatedAsset_on_taskId", on: "generatedAsset", columns: ["taskId"])
            try db.create(index: "generatedAsset_on_status", on: "generatedAsset", columns: ["status"])
        }

        migrator.registerMigration("v12_asset_versioning") { db in
            try db.alter(table: "generatedAsset") { t in
                t.add(column: "version", .integer).notNull().defaults(to: 1)
                t.add(column: "thumbnailPath", .text)
                t.add(column: "checksum", .text)
                t.add(column: "parentAssetId", .text)
                    .references("generatedAsset", onDelete: .setNull)
            }
            try db.create(index: "generatedAsset_on_parentAssetId",
                          on: "generatedAsset", columns: ["parentAssetId"])
        }

        migrator.registerMigration("v13_publishing") { db in
            try db.create(table: "publishingChannel") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("channelType", .text).notNull()
                t.column("credentialsJSON", .text).notNull().defaults(to: "{}")
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("defaultTags", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "publication") { t in
                t.primaryKey("id", .text).notNull()
                t.column("assetId", .text).notNull()
                    .references("generatedAsset", onDelete: .cascade)
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("channelId", .text).notNull()
                    .references("publishingChannel", onDelete: .cascade)
                t.column("status", .text).notNull().defaults(to: "scheduled")
                t.column("externalId", .text)
                t.column("publishedUrl", .text)
                t.column("scheduledAt", .datetime)
                t.column("publishedAt", .datetime)
                t.column("errorMessage", .text)
                t.column("exportFormat", .text).notNull().defaults(to: "markdown")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "publication_on_assetId", on: "publication", columns: ["assetId"])
            try db.create(index: "publication_on_projectId", on: "publication", columns: ["projectId"])
            try db.create(index: "publication_on_status", on: "publication", columns: ["status"])
        }

        migrator.registerMigration("v14_deployment_auto_fix") { db in
            // Track the coder fix task spawned to repair a failed deployment
            try db.alter(table: "deployment") { t in
                t.add(column: "fixTaskId", .text)
            }
            // Track how many auto-fix attempts have been made
            try db.alter(table: "deployment") { t in
                t.add(column: "autoFixAttempts", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v15_revision_prompt") { db in
            try db.alter(table: "agentTask") { t in
                t.add(column: "revisionPrompt", .text)
            }
        }

        migrator.registerMigration("v16_branching_strategy") { db in
            try db.alter(table: "feature") { t in
                t.add(column: "integrationPrNumber", .integer)
            }
            try db.alter(table: "project") { t in
                t.add(column: "stagingPrNumber", .integer)
            }
        }

        migrator.registerMigration("v17_skill_persona") { db in
            try db.alter(table: "agentTask") { t in
                t.add(column: "skillPersona", .text)
            }
        }

        return migrator
    }
}

// MARK: - Factory

extension AppDatabase {
    /// Creates the default database in Application Support.
    public static func makeDefault() throws -> AppDatabase {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL.appendingPathComponent("CreedFlow", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let dbURL = directoryURL.appendingPathComponent("creedflow.sqlite")
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        return try AppDatabase(dbQueue)
    }

    /// Creates an in-memory database for testing.
    public static func makeEmpty() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: .init())
        return try AppDatabase(dbQueue)
    }
}

// MARK: - SwiftUI Environment

import SwiftUI

struct AppDatabaseKey: EnvironmentKey {
    static let defaultValue: AppDatabase? = nil
}

public extension EnvironmentValues {
    var appDatabase: AppDatabase? {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}
