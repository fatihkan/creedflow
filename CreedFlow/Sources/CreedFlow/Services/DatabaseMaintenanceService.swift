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

    /// Formats bytes into a human-readable string.
    package static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
