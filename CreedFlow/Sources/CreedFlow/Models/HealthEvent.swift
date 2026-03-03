import Foundation
import GRDB

/// Records a health check result for a backend CLI or MCP server.
package struct HealthEvent: Codable, Identifiable, Equatable {
    package var id: UUID
    package var targetType: TargetType
    package var targetName: String
    package var status: HealthStatus
    package var responseTimeMs: Int?
    package var errorMessage: String?
    package var metadata: String?
    package var checkedAt: Date

    package enum TargetType: String, Codable, CaseIterable, DatabaseValueConvertible {
        case backend
        case mcp
    }

    package enum HealthStatus: String, Codable, CaseIterable, DatabaseValueConvertible {
        case healthy
        case degraded
        case unhealthy
        case unknown
    }

    package init(
        id: UUID = UUID(),
        targetType: TargetType,
        targetName: String,
        status: HealthStatus,
        responseTimeMs: Int? = nil,
        errorMessage: String? = nil,
        metadata: String? = nil,
        checkedAt: Date = Date()
    ) {
        self.id = id
        self.targetType = targetType
        self.targetName = targetName
        self.status = status
        self.responseTimeMs = responseTimeMs
        self.errorMessage = errorMessage
        self.metadata = metadata
        self.checkedAt = checkedAt
    }
}

// MARK: - Persistence

extension HealthEvent: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "healthEvent"
}
