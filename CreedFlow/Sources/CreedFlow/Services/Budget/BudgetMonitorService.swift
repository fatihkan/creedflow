import Foundation
import GRDB
import os

/// Monitors cost budgets every 60 seconds, emits notifications at warn/critical
/// thresholds, and signals the Orchestrator to defer tasks when budgets are exceeded.
actor BudgetMonitorService {
    private let dbQueue: DatabaseQueue
    private let notificationService: NotificationService
    private let logger = Logger(subsystem: "com.creedflow", category: "BudgetMonitorService")
    private let checkInterval: TimeInterval = 60
    private var pollingTask: Task<Void, Never>?

    /// Budgets that have pauseOnExceed=true and are currently over limit.
    /// Keyed by scope: "global" or project UUID string.
    private var pausedScopes: Set<String> = []

    init(dbQueue: DatabaseQueue, notificationService: NotificationService) {
        self.dbQueue = dbQueue
        self.notificationService = notificationService
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkBudgets()
                try? await Task.sleep(for: .seconds(self?.checkInterval ?? 60))
            }
        }
        logger.info("Budget monitor started (interval: \(self.checkInterval)s)")
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        logger.info("Budget monitor stopped")
    }

    /// Called by Orchestrator before dispatching a task.
    /// Returns true if the task should be deferred due to budget limits.
    func shouldPauseForBudget(projectId: UUID?) -> Bool {
        if pausedScopes.contains("global") { return true }
        if let pid = projectId, pausedScopes.contains(pid.uuidString) { return true }
        return false
    }

    // MARK: - Budget Checking

    private func checkBudgets() async {
        do {
            let budgets = try await dbQueue.read { db in
                try CostBudget
                    .filter(Column("isEnabled") == true)
                    .fetchAll(db)
            }

            var newPausedScopes: Set<String> = []

            for budget in budgets {
                let currentSpend = try await currentSpendForBudget(budget)
                let percentage = budget.limitUsd > 0 ? currentSpend / budget.limitUsd : 0

                // Check critical threshold
                if percentage >= budget.criticalThreshold {
                    await emitAlertIfNeeded(budget: budget, thresholdType: .critical, currentSpend: currentSpend, percentage: percentage)
                }
                // Check warn threshold
                else if percentage >= budget.warnThreshold {
                    await emitAlertIfNeeded(budget: budget, thresholdType: .warn, currentSpend: currentSpend, percentage: percentage)
                }

                // Check if budget exceeded and should pause
                if percentage >= 1.0 && budget.pauseOnExceed {
                    let scopeKey = budget.scope == .global ? "global" : (budget.projectId?.uuidString ?? "global")
                    newPausedScopes.insert(scopeKey)
                    await emitAlertIfNeeded(budget: budget, thresholdType: .exceeded, currentSpend: currentSpend, percentage: percentage)
                }
            }

            pausedScopes = newPausedScopes
        } catch {
            logger.error("Budget check failed: \(error)")
        }
    }

    private func currentSpendForBudget(_ budget: CostBudget) async throws -> Double {
        let periodStart = Self.periodStart(for: budget.period)

        return try await dbQueue.read { db in
            var sql = "SELECT COALESCE(SUM(costUSD), 0) FROM costTracking WHERE createdAt >= ?"
            var arguments: [DatabaseValueConvertible] = [periodStart]

            if budget.scope == .project, let projectId = budget.projectId {
                sql += " AND projectId = ?"
                arguments.append(projectId.uuidString)
            }

            return try Double.fetchOne(db, sql: sql, arguments: StatementArguments(arguments)) ?? 0
        }
    }

    private func emitAlertIfNeeded(
        budget: CostBudget,
        thresholdType: BudgetAlert.ThresholdType,
        currentSpend: Double,
        percentage: Double
    ) async {
        // Check for recent alert of same type for this budget (within the current period)
        let periodStart = Self.periodStart(for: budget.period)
        let hasRecentAlert = (try? await dbQueue.read { db in
            try BudgetAlert
                .filter(Column("budgetId") == budget.id.uuidString)
                .filter(Column("thresholdType") == thresholdType.rawValue)
                .filter(Column("createdAt") >= periodStart)
                .fetchOne(db) != nil
        }) ?? false

        guard !hasRecentAlert else { return }

        // Insert alert record
        do {
            try await dbQueue.write { db in
                var alert = BudgetAlert(
                    budgetId: budget.id,
                    thresholdType: thresholdType,
                    currentSpend: currentSpend,
                    limitUsd: budget.limitUsd,
                    percentage: percentage
                )
                try alert.insert(db)
            }
        } catch {
            logger.error("Failed to insert budget alert: \(error)")
            return
        }

        // Emit notification
        let severity: AppNotification.Severity = thresholdType == .warn ? .warning : .error
        let pct = Int(percentage * 100)
        let scopeLabel = budget.scope == .global ? "Global" : "Project"
        let title = thresholdType == .exceeded
            ? "Budget Exceeded"
            : "Budget \(thresholdType == .critical ? "Critical" : "Warning")"
        let message = "\(scopeLabel) \(budget.period.rawValue) budget: $\(String(format: "%.2f", currentSpend)) / $\(String(format: "%.2f", budget.limitUsd)) (\(pct)%)"

        await notificationService.emit(
            category: .budget,
            severity: severity,
            title: title,
            message: message
        )

        if thresholdType == .exceeded && budget.pauseOnExceed {
            logger.warning("Budget exceeded — tasks will be deferred for \(scopeLabel, privacy: .public) scope")
        }
    }

    // MARK: - Helpers

    private static func periodStart(for period: CostBudget.Period) -> Date {
        let calendar = Calendar.current
        let now = Date()
        switch period {
        case .daily:
            return calendar.startOfDay(for: now)
        case .weekly:
            let weekday = calendar.component(.weekday, from: now)
            return calendar.date(byAdding: .day, value: -(weekday - calendar.firstWeekday), to: calendar.startOfDay(for: now))!
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: now)
            return calendar.date(from: components)!
        }
    }
}
