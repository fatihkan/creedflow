import Foundation
import GRDB

struct Feature: Codable, Identifiable, Equatable {
    var id: UUID
    var projectId: UUID
    var name: String
    var description: String
    var priority: Int
    var status: Status
    var createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable, CaseIterable, DatabaseValueConvertible {
        case pending
        case inProgress = "in_progress"
        case completed
        case failed
    }

    init(
        id: UUID = UUID(),
        projectId: UUID,
        name: String,
        description: String,
        priority: Int = 0,
        status: Status = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.description = description
        self.priority = priority
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension Feature: FetchableRecord, PersistableRecord {
    static let databaseTableName = "feature"

    static let project = belongsTo(Project.self)
    static let tasks = hasMany(AgentTask.self)

    var project: QueryInterfaceRequest<Project> {
        request(for: Feature.project)
    }

    var tasks: QueryInterfaceRequest<AgentTask> {
        request(for: Feature.tasks)
    }
}
