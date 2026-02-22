import Foundation
import GRDB

struct Deployment: Codable, Identifiable, Equatable {
    var id: UUID
    var projectId: UUID
    var environment: Environment
    var status: Status
    var version: String
    var commitHash: String?
    var deployedBy: String
    var rollbackFrom: UUID?
    var logs: String?
    var createdAt: Date
    var completedAt: Date?

    enum Environment: String, Codable, CaseIterable, DatabaseValueConvertible {
        case staging
        case production
    }

    enum Status: String, Codable, CaseIterable, DatabaseValueConvertible {
        case pending
        case inProgress = "in_progress"
        case success
        case failed
        case rolledBack = "rolled_back"
    }

    init(
        id: UUID = UUID(),
        projectId: UUID,
        environment: Environment = .staging,
        status: Status = .pending,
        version: String,
        commitHash: String? = nil,
        deployedBy: String = "system",
        rollbackFrom: UUID? = nil,
        logs: String? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.environment = environment
        self.status = status
        self.version = version
        self.commitHash = commitHash
        self.deployedBy = deployedBy
        self.rollbackFrom = rollbackFrom
        self.logs = logs
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

// MARK: - Persistence

extension Deployment: FetchableRecord, PersistableRecord {
    static let databaseTableName = "deployment"

    static let project = belongsTo(Project.self)
}
