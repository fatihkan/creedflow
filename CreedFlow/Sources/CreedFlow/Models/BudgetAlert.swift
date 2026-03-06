import Foundation
import GRDB

/// Records when a budget threshold was crossed — prevents duplicate notifications
/// for the same threshold on the same budget within a period.
package struct BudgetAlert: Codable, Identifiable, Equatable {
    package var id: UUID
    package var budgetId: UUID
    package var thresholdType: ThresholdType
    package var currentSpend: Double
    package var limitUsd: Double
    package var percentage: Double
    package var acknowledgedAt: Date?
    package var createdAt: Date

    package enum ThresholdType: String, Codable, DatabaseValueConvertible {
        case warn
        case critical
        case exceeded
    }

    package init(
        id: UUID = UUID(),
        budgetId: UUID,
        thresholdType: ThresholdType,
        currentSpend: Double,
        limitUsd: Double,
        percentage: Double,
        acknowledgedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.budgetId = budgetId
        self.thresholdType = thresholdType
        self.currentSpend = currentSpend
        self.limitUsd = limitUsd
        self.percentage = percentage
        self.acknowledgedAt = acknowledgedAt
        self.createdAt = createdAt
    }
}

// MARK: - Persistence

extension BudgetAlert: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "budgetAlert"

    static let budget = belongsTo(CostBudget.self)
}
