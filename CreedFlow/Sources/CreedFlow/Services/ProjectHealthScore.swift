import SwiftUI
import GRDB

package struct ProjectHealthScore {
    package let overall: Int          // 0-100
    package let passRate: Double      // 0..1
    package let qualityScore: Double  // 0..1
    package let deployRate: Double    // 0..1
    package let recency: Double       // 0..1
    package let taskCount: Int

    package var color: Color {
        if taskCount == 0 { return .gray }
        if overall >= 70 { return .green }
        if overall >= 40 { return .orange }
        return .red
    }

    package var label: String {
        taskCount == 0 ? "N/A" : "\(overall)"
    }

    package static let empty = ProjectHealthScore(
        overall: 0, passRate: 0, qualityScore: 0, deployRate: 0, recency: 0, taskCount: 0
    )

    /// Compute health score for a project from existing agentTask, review, and deployment tables.
    package static func compute(db: Database, projectId: UUID) throws -> ProjectHealthScore {
        let projectIdStr = projectId.uuidString

        // 1. Task pass rate: passed / (passed + failed) — excludes queued/inProgress
        let row = try Row.fetchOne(db, sql: """
            SELECT
                COUNT(*) AS total,
                SUM(CASE WHEN status = 'passed' THEN 1 ELSE 0 END) AS passed,
                SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed,
                MAX(updatedAt) AS lastActivity
            FROM agentTask
            WHERE projectId = ? AND archivedAt IS NULL
            """, arguments: [projectIdStr])

        let totalTasks: Int = row?["total"] ?? 0
        let passedCount: Int = row?["passed"] ?? 0
        let failedCount: Int = row?["failed"] ?? 0
        let lastActivityStr: String? = row?["lastActivity"]

        if totalTasks == 0 {
            return .empty
        }

        let resolved = passedCount + failedCount
        let passRate = resolved > 0 ? Double(passedCount) / Double(resolved) : 0.0

        // 2. Avg review score / 10 — normalized to 0..1
        let avgScore: Double = try Double.fetchOne(db, sql: """
            SELECT COALESCE(AVG(r.score), 0)
            FROM review r
            JOIN agentTask t ON r.taskId = t.id
            WHERE t.projectId = ? AND t.archivedAt IS NULL
            """, arguments: [projectIdStr]) ?? 0
        let qualityScore = min(avgScore / 10.0, 1.0)

        // 3. Deploy success rate
        let deployRow = try Row.fetchOne(db, sql: """
            SELECT
                COUNT(*) AS total,
                SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS succeeded
            FROM deployment
            WHERE projectId = ?
            """, arguments: [projectIdStr])
        let totalDeploys: Int = deployRow?["total"] ?? 0
        let succeededDeploys: Int = deployRow?["succeeded"] ?? 0
        let deployRate = totalDeploys > 0 ? Double(succeededDeploys) / Double(totalDeploys) : 0.0

        // 4. Recency: 1.0 if activity in last 24h, decays to 0 over 7 days
        var recency = 0.0
        if let activityStr = lastActivityStr,
           let lastDate = ProjectHealthScore.parseDate(activityStr) {
            let hoursAgo = Date().timeIntervalSince(lastDate) / 3600.0
            if hoursAgo <= 24 {
                recency = 1.0
            } else if hoursAgo < 168 { // 7 days
                recency = max(0, 1.0 - (hoursAgo - 24) / (168 - 24))
            }
        }

        // Weighted composite
        let score = (0.35 * passRate + 0.25 * qualityScore + 0.20 * deployRate + 0.20 * recency) * 100
        let overall = min(100, max(0, Int(score.rounded())))

        return ProjectHealthScore(
            overall: overall,
            passRate: passRate,
            qualityScore: qualityScore,
            deployRate: deployRate,
            recency: recency,
            taskCount: totalTasks
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: string) { return date }
        // Fallback without milliseconds
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)
    }
}
