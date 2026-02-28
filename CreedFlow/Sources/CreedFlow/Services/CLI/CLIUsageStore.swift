import Foundation
import GRDB

/// Aggregates CLI usage data from CostTracking for sidebar display.
/// Tracks per-backend token/cost totals for two time windows: last 4 hours and last 7 days.
@Observable
final class CLIUsageStore {

    struct UsageWindow {
        var tokens: Int = 0
        var cost: Double = 0
        var taskCount: Int = 0
    }

    struct BackendUsage {
        let backend: CLIBackendType
        var last4h: UsageWindow = UsageWindow()
        var lastWeek: UsageWindow = UsageWindow()
    }

    private(set) var usages: [CLIBackendType: BackendUsage] = [:]

    /// Cloud backends we track (local LLMs are unlimited, no need to show).
    static let trackedBackends: [CLIBackendType] = [.claude, .codex, .gemini]

    func usage(for backend: CLIBackendType) -> BackendUsage {
        usages[backend] ?? BackendUsage(backend: backend)
    }

    /// Start observing CostTracking changes and aggregate per-backend usage.
    func observe(in dbQueue: DatabaseQueue) async {
        let observation = ValueObservation.tracking { db -> [CLIBackendType: BackendUsage] in
            let now = Date()
            let fourHoursAgo = now.addingTimeInterval(-4 * 3600)
            let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)

            var result: [CLIBackendType: BackendUsage] = [:]
            for backendType in CLIUsageStore.trackedBackends {
                result[backendType] = BackendUsage(backend: backendType)
            }

            // Last 4 hours
            let rows4h = try Row.fetchAll(db, sql: """
                SELECT backend,
                       COALESCE(SUM(inputTokens + outputTokens), 0) AS totalTokens,
                       COALESCE(SUM(costUSD), 0) AS totalCost,
                       COUNT(*) AS taskCount
                FROM costTracking
                WHERE createdAt >= ? AND backend IS NOT NULL
                GROUP BY backend
                """, arguments: [fourHoursAgo])

            for row in rows4h {
                guard let rawBackend: String = row["backend"],
                      let backendType = CLIBackendType(rawValue: rawBackend),
                      CLIUsageStore.trackedBackends.contains(backendType) else { continue }
                result[backendType]?.last4h = UsageWindow(
                    tokens: row["totalTokens"],
                    cost: row["totalCost"],
                    taskCount: row["taskCount"]
                )
            }

            // Last 7 days
            let rows7d = try Row.fetchAll(db, sql: """
                SELECT backend,
                       COALESCE(SUM(inputTokens + outputTokens), 0) AS totalTokens,
                       COALESCE(SUM(costUSD), 0) AS totalCost,
                       COUNT(*) AS taskCount
                FROM costTracking
                WHERE createdAt >= ? AND backend IS NOT NULL
                GROUP BY backend
                """, arguments: [weekAgo])

            for row in rows7d {
                guard let rawBackend: String = row["backend"],
                      let backendType = CLIBackendType(rawValue: rawBackend),
                      CLIUsageStore.trackedBackends.contains(backendType) else { continue }
                result[backendType]?.lastWeek = UsageWindow(
                    tokens: row["totalTokens"],
                    cost: row["totalCost"],
                    taskCount: row["taskCount"]
                )
            }

            return result
        }

        do {
            for try await value in observation.values(in: dbQueue) {
                usages = value
            }
        } catch {
            // Observation error — usage bars may be stale
        }
    }
}
