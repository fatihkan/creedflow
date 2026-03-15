import Foundation
import GRDB

/// Maps an external issue (Linear/Jira) to an AgentTask for sync tracking.
package struct IssueMapping: Codable, Identifiable, Equatable {
    package var id: UUID
    package var configId: UUID
    package var taskId: UUID
    package var externalIssueId: String
    package var externalIdentifier: String
    package var externalUrl: String?
    package var syncStatus: SyncStatus
    package var lastSyncedAt: Date?
    package var createdAt: Date

    package enum SyncStatus: String, Codable, CaseIterable, DatabaseValueConvertible {
        case imported
        case synced
        case syncFailed = "sync_failed"
    }

    package init(
        id: UUID = UUID(),
        configId: UUID,
        taskId: UUID,
        externalIssueId: String,
        externalIdentifier: String,
        externalUrl: String? = nil,
        syncStatus: SyncStatus = .imported,
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.configId = configId
        self.taskId = taskId
        self.externalIssueId = externalIssueId
        self.externalIdentifier = externalIdentifier
        self.externalUrl = externalUrl
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
    }
}

// MARK: - Persistence

extension IssueMapping: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "issueMapping"

    static let config = belongsTo(IssueTrackingConfig.self, using: ForeignKey(["configId"]))
    static let task = belongsTo(AgentTask.self, using: ForeignKey(["taskId"]))
}
