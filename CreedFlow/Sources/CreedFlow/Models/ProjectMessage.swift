import Foundation
import GRDB

/// A chat message in the project planning conversation.
package struct ProjectMessage: Codable, Identifiable, Equatable {
    package var id: UUID
    package var projectId: UUID
    package var role: Role
    package var content: String
    package var backend: String?
    package var costUSD: Double?
    package var durationMs: Int64?
    package var metadata: String?
    package var createdAt: Date

    package enum Role: String, Codable, DatabaseValueConvertible {
        case user
        case assistant
        case system
    }

    package init(
        id: UUID = UUID(),
        projectId: UUID,
        role: Role,
        content: String,
        backend: String? = nil,
        costUSD: Double? = nil,
        durationMs: Int64? = nil,
        metadata: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.role = role
        self.content = content
        self.backend = backend
        self.costUSD = costUSD
        self.durationMs = durationMs
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

// MARK: - Persistence

extension ProjectMessage: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "projectMessage"

    static let project = belongsTo(Project.self)
}
