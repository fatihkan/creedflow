import Foundation
import GRDB

package struct Project: Codable, Identifiable, Equatable {
    package var id: UUID
    package var name: String
    package var description: String
    package var techStack: String
    package var status: Status
    package var directoryPath: String
    package var projectType: ProjectType
    package var telegramChatId: Int64?
    package var createdAt: Date
    package var updatedAt: Date

    package enum ProjectType: String, Codable, CaseIterable, DatabaseValueConvertible {
        case software
        case content      // Blog, copywriting, documentation
        case image        // Image generation, design
        case video        // Video generation, editing
        case general      // Other/mixed
    }

    package enum Status: String, Codable, CaseIterable, DatabaseValueConvertible {
        case planning
        case analyzing
        case inProgress = "in_progress"
        case reviewing
        case deploying
        case completed
        case failed
        case paused
    }

    package init(
        id: UUID = UUID(),
        name: String,
        description: String,
        techStack: String = "",
        status: Status = .planning,
        directoryPath: String = "",
        projectType: ProjectType = .software,
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
        self.projectType = projectType
        self.telegramChatId = telegramChatId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension Project: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "project"

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
