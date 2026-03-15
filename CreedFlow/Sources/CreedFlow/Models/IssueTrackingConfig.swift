import Foundation
import GRDB

/// Per-project issue tracker integration config (Linear, Jira).
package struct IssueTrackingConfig: Codable, Identifiable, Equatable {
    package var id: UUID
    package var projectId: UUID
    package var provider: Provider
    package var name: String
    package var credentialsJSON: String
    package var configJSON: String
    package var isEnabled: Bool
    package var syncBackEnabled: Bool
    package var lastSyncAt: Date?
    package var createdAt: Date
    package var updatedAt: Date

    package enum Provider: String, Codable, CaseIterable, DatabaseValueConvertible {
        case linear
        case jira
    }

    package init(
        id: UUID = UUID(),
        projectId: UUID,
        provider: Provider,
        name: String,
        credentialsJSON: String = "{}",
        configJSON: String = "{}",
        isEnabled: Bool = true,
        syncBackEnabled: Bool = false,
        lastSyncAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.provider = provider
        self.name = name
        self.credentialsJSON = credentialsJSON
        self.configJSON = configJSON
        self.isEnabled = isEnabled
        self.syncBackEnabled = syncBackEnabled
        self.lastSyncAt = lastSyncAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension IssueTrackingConfig: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "issueTrackingConfig"

    static let project = belongsTo(Project.self)
    static let issueMappings = hasMany(IssueMapping.self, using: ForeignKey(["configId"]))
}
