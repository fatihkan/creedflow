import Foundation
import GRDB
import os.log

/// The application database — manages SQLite connection, migrations, and provides
/// a shared `DatabaseQueue` for all read/write operations.
struct AppDatabase {
    let dbQueue: DatabaseQueue

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

        return migrator
    }
}

// MARK: - Factory

extension AppDatabase {
    /// Creates the default database in Application Support.
    static func makeDefault() throws -> AppDatabase {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL.appendingPathComponent("CodeForge", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let dbURL = directoryURL.appendingPathComponent("codeforge.sqlite")
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        return try AppDatabase(dbQueue)
    }

    /// Creates an in-memory database for testing.
    static func makeEmpty() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: .init())
        return try AppDatabase(dbQueue)
    }
}

// MARK: - SwiftUI Environment

import SwiftUI

private struct AppDatabaseKey: EnvironmentKey {
    static let defaultValue: AppDatabase? = nil
}

extension EnvironmentValues {
    var appDatabase: AppDatabase? {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}
