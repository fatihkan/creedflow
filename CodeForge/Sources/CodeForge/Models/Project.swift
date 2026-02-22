import Foundation
import GRDB

struct Project: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var description: String
    var techStack: String
    var status: Status
    var directoryPath: String
    var telegramChatId: Int64?
    var createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable, CaseIterable, DatabaseValueConvertible {
        case planning
        case analyzing
        case inProgress = "in_progress"
        case reviewing
        case deploying
        case completed
        case failed
        case paused
    }

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        techStack: String = "",
        status: Status = .planning,
        directoryPath: String = "",
        telegramChatId: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.techStack = techStack
        self.status = status
        self.directoryPath = directoryPath
        self.telegramChatId = telegramChatId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension Project: FetchableRecord, PersistableRecord {
    static let databaseTableName = "project"

    static let features = hasMany(Feature.self)
    static let tasks = hasMany(AgentTask.self)
    static let deployments = hasMany(Deployment.self)
    static let costTrackings = hasMany(CostTracking.self)

    var features: QueryInterfaceRequest<Feature> {
        request(for: Project.features)
    }

    var tasks: QueryInterfaceRequest<AgentTask> {
        request(for: Project.tasks)
    }
}
