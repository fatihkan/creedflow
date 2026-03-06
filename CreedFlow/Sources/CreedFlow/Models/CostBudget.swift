import Foundation
import GRDB

/// Configurable spending limit — either global or per-project, with daily/weekly/monthly periods.
/// BudgetMonitorService checks these periodically and emits alerts at warn/critical thresholds.
package struct CostBudget: Codable, Identifiable, Equatable {
    package var id: UUID
    package var scope: Scope
    package var projectId: UUID?
    package var period: Period
    package var limitUsd: Double
    package var warnThreshold: Double
    package var criticalThreshold: Double
    package var pauseOnExceed: Bool
    package var isEnabled: Bool
    package var createdAt: Date
    package var updatedAt: Date

    package enum Scope: String, Codable, CaseIterable, DatabaseValueConvertible {
        case global
        case project
    }

    package enum Period: String, Codable, CaseIterable, DatabaseValueConvertible {
        case daily
        case weekly
        case monthly
    }

    package init(
        id: UUID = UUID(),
        scope: Scope = .global,
        projectId: UUID? = nil,
        period: Period = .monthly,
        limitUsd: Double = 50.0,
        warnThreshold: Double = 0.80,
        criticalThreshold: Double = 0.95,
        pauseOnExceed: Bool = false,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.projectId = projectId
        self.period = period
        self.limitUsd = limitUsd
        self.warnThreshold = warnThreshold
        self.criticalThreshold = criticalThreshold
        self.pauseOnExceed = pauseOnExceed
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension CostBudget: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "costBudget"

    static let project = belongsTo(Project.self)
}
