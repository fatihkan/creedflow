import Foundation
import GRDB
import os

/// Periodically computes performance scores for each CLI backend based on
/// cost efficiency, speed, reliability, and quality metrics from the last 30 days.
/// Scores are persisted to the `backendScore` table and consumed by BackendRouter
/// for weighted backend selection.
actor BackendScoringService {
    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: "com.creedflow", category: "BackendScoringService")
    private let updateInterval: TimeInterval = 300 // 5 minutes
    private var pollingTask: Task<Void, Never>?

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.computeScores()
                try? await Task.sleep(for: .seconds(self?.updateInterval ?? 300))
            }
        }
        logger.info("Backend scoring service started (interval: \(self.updateInterval)s)")
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        logger.info("Backend scoring service stopped")
    }

    /// Returns the current composite score for a backend, or nil if not enough data.
    func score(for backendType: CLIBackendType) async -> BackendScore? {
        try? await dbQueue.read { db in
            try BackendScore
                .filter(Column("backendType") == backendType.rawValue)
                .fetchOne(db)
        }
    }

    /// Returns all backend scores.
    func allScores() async -> [BackendScore] {
        (try? await dbQueue.read { db in
            try BackendScore.fetchAll(db)
        }) ?? []
    }

    // MARK: - Scoring Algorithm

    private func computeScores() async {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        do {
            try await dbQueue.write { [logger] db in
                // Gather per-backend metrics from agentTask + costTracking + review
                let stats = try Self.fetchBackendStats(db: db, since: thirtyDaysAgo)
                guard !stats.isEmpty else { return }

                // Compute min/max for normalization
                let allCosts = stats.map(\.avgCostPerTask)
                let allDurations = stats.map(\.avgDurationMs)
                let costMin = allCosts.min() ?? 0
                let costMax = allCosts.max() ?? 1
                let durationMin = allDurations.min() ?? 0
                let durationMax = allDurations.max() ?? 1

                for stat in stats {
                    let costEfficiency: Double
                    let speed: Double

                    if stat.sampleSize < 5 {
                        // Not enough data — use baseline
                        costEfficiency = 0.5
                        speed = 0.5
                    } else {
                        costEfficiency = 1.0 - Self.normalize(stat.avgCostPerTask, min: costMin, max: costMax)
                        speed = 1.0 - Self.normalize(stat.avgDurationMs, min: durationMin, max: durationMax)
                    }

                    let reliability = stat.sampleSize < 5 ? 0.5 : stat.reliability
                    let quality = stat.sampleSize < 5 ? 0.5 : stat.quality

                    let composite = 0.25 * costEfficiency + 0.25 * speed + 0.30 * reliability + 0.20 * quality

                    // UPSERT: check if score exists for this backend type
                    if var existing = try BackendScore
                        .filter(Column("backendType") == stat.backendType)
                        .fetchOne(db) {
                        existing.costEfficiency = costEfficiency
                        existing.speed = speed
                        existing.reliability = reliability
                        existing.quality = quality
                        existing.compositeScore = composite
                        existing.sampleSize = stat.sampleSize
                        existing.updatedAt = Date()
                        try existing.update(db)
                    } else {
                        var score = BackendScore(
                            backendType: CLIBackendType(rawValue: stat.backendType) ?? .claude,
                            costEfficiency: costEfficiency,
                            speed: speed,
                            reliability: reliability,
                            quality: quality,
                            compositeScore: composite,
                            sampleSize: stat.sampleSize,
                            updatedAt: Date()
                        )
                        try score.insert(db)
                    }

                    logger.debug("Score for \(stat.backendType): cost=\(costEfficiency, format: .fixed(precision: 2)) speed=\(speed, format: .fixed(precision: 2)) rel=\(reliability, format: .fixed(precision: 2)) qual=\(quality, format: .fixed(precision: 2)) composite=\(composite, format: .fixed(precision: 2)) (n=\(stat.sampleSize))")
                }
            }
        } catch {
            logger.error("Failed to compute backend scores: \(error)")
        }
    }

    // MARK: - Helpers

    private static func normalize(_ value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return 0.5 }
        return (value - min) / (max - min)
    }

    private struct BackendStat {
        let backendType: String
        let avgCostPerTask: Double
        let avgDurationMs: Double
        let reliability: Double  // passed / total
        let quality: Double      // avg review score / 10
        let sampleSize: Int
    }

    private static func fetchBackendStats(db: Database, since: Date) throws -> [BackendStat] {
        // Query: aggregate task metrics grouped by backend
        let sql = """
            SELECT
                t.backend,
                COUNT(*) AS totalCount,
                AVG(COALESCE(c.costUSD, 0)) AS avgCost,
                AVG(COALESCE(t.durationMs, 0)) AS avgDuration,
                SUM(CASE WHEN t.status = 'passed' THEN 1 ELSE 0 END) AS passedCount,
                COALESCE(AVG(r.score), 5.0) AS avgReviewScore
            FROM agentTask t
            LEFT JOIN costTracking c ON c.taskId = t.id
            LEFT JOIN review r ON r.taskId = t.id
            WHERE t.backend IS NOT NULL
              AND t.status IN ('passed', 'failed', 'needs_revision')
              AND t.updatedAt >= ?
            GROUP BY t.backend
            """

        let rows = try Row.fetchAll(db, sql: sql, arguments: [since])
        return rows.compactMap { row -> BackendStat? in
            guard let backend: String = row["backend"] else { return nil }
            let totalCount: Int = row["totalCount"] ?? 0
            let avgCost: Double = row["avgCost"] ?? 0
            let avgDuration: Double = row["avgDuration"] ?? 0
            let passedCount: Int = row["passedCount"] ?? 0
            let avgReviewScore: Double = row["avgReviewScore"] ?? 5.0

            return BackendStat(
                backendType: backend,
                avgCostPerTask: avgCost,
                avgDurationMs: avgDuration,
                reliability: totalCount > 0 ? Double(passedCount) / Double(totalCount) : 0.5,
                quality: avgReviewScore / 10.0,
                sampleSize: totalCount
            )
        }
    }
}
