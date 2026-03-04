import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "com.creedflow", category: "DatabaseMaintenance")

/// Provides database maintenance operations: file size, table counts, vacuum, backup, log pruning.
@Observable
package class DatabaseMaintenanceService {
    package var isWorking = false
    package var lastResult: String?

    private let dbQueue: DatabaseQueue
    private let databasePath: String

    package init(dbQueue: DatabaseQueue, databasePath: String) {
        self.dbQueue = dbQueue
        self.databasePath = databasePath
    }

    /// Returns the database file size in bytes.
    package func databaseFileSize() -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: databasePath)
        return (attrs?[.size] as? Int64) ?? 0
    }

    /// Returns a dictionary of table name → row count.
    package func tableCounts() throws -> [(table: String, count: Int)] {
        try dbQueue.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' ORDER BY name")
            return try tables.map { table in
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(table)\"") ?? 0
                return (table: table, count: count)
            }
        }
    }

    /// Runs VACUUM to compact the database.
    package func vacuum() async throws {
        isWorking = true
        defer { isWorking = false }
        try await dbQueue.vacuum()
        logger.info("Database vacuumed successfully")
        lastResult = "Vacuum completed"
    }

    /// Creates a backup of the database at the given URL using VACUUM INTO.
    package func backup(to url: URL) async throws {
        isWorking = true
        defer { isWorking = false }
        try await dbQueue.write { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [url.path])
        }
        logger.info("Database backed up to \(url.path)")
        lastResult = "Backup saved to \(url.lastPathComponent)"
    }

    /// Deletes agent logs older than the specified number of days.
    package func pruneLogs(olderThanDays days: Int) async throws -> Int {
        isWorking = true
        defer { isWorking = false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let count = try await dbQueue.write { db in
            try AgentLog
                .filter(Column("createdAt") < cutoff)
                .deleteAll(db)
        }
        logger.info("Pruned \(count) logs older than \(days) days")
        lastResult = "Pruned \(count) log entries"
        return count
    }

    /// Exports all database tables as a JSON file.
    package func exportAsJSON(to url: URL) async throws {
        isWorking = true
        defer { isWorking = false }

        let data = try await dbQueue.read { db -> [String: Any] in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' ORDER BY name")
            var export: [String: Any] = [:]
            for table in tables {
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\"")
                let rowDicts: [[String: Any]] = rows.map { row in
                    var dict: [String: Any] = [:]
                    for (column, dbValue) in row {
                        if dbValue.isNull {
                            dict[column] = NSNull()
                        } else if let int = Int64.fromDatabaseValue(dbValue) {
                            dict[column] = int
                        } else if let double = Double.fromDatabaseValue(dbValue) {
                            dict[column] = double
                        } else if let string = String.fromDatabaseValue(dbValue) {
                            dict[column] = string
                        } else {
                            dict[column] = dbValue.description
                        }
                    }
                    return dict
                }
                export[table] = rowDicts
            }
            return export
        }

        let jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: url)
        logger.info("Database exported as JSON to \(url.path)")
        lastResult = "Exported to \(url.lastPathComponent)"
    }

    /// Deletes all user data from the database (keeps schema intact).
    package func factoryReset() async throws {
        isWorking = true
        defer { isWorking = false }

        let tablesToClear = [
            "promptUsage", "promptChainStep", "promptChain", "promptVersion",
            "promptTag", "prompt", "taskDependency",
            "publication", "publishingChannel", "generatedAsset",
            "review", "agentLog", "costTracking", "deployment",
            "archivedTask", "agentTask", "feature",
            "projectChatMessage", "project",
            "appNotification", "healthEvent", "mcpServerConfig"
        ]

        try await dbQueue.write { db in
            for table in tablesToClear {
                try? db.execute(sql: "DELETE FROM \"\(table)\"")
            }
        }
        logger.info("Factory reset: all user data cleared")
        lastResult = "Factory reset complete"
    }

    /// Formats bytes into a human-readable string.
    package static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
