import Foundation
import GRDB

/// Named "AgentTask" to avoid collision with Swift.Task
package struct AgentTask: Codable, Identifiable, Equatable {
    package var id: UUID
    package var projectId: UUID
    package var featureId: UUID?
    package var agentType: AgentType
    package var title: String
    package var description: String
    package var priority: Int
    package var status: Status
    package var result: String?
    package var errorMessage: String?
    package var retryCount: Int
    package var maxRetries: Int
    package var sessionId: String?
    package var branchName: String?
    package var prNumber: Int?
    package var costUSD: Double?
    package var durationMs: Int64?
    package var createdAt: Date
    package var updatedAt: Date
    package var startedAt: Date?
    package var completedAt: Date?

    package enum AgentType: String, Codable, CaseIterable, DatabaseValueConvertible {
        case analyzer
        case coder
        case reviewer
        case tester
        case devops
        case monitor
    }

    package enum Status: String, Codable, CaseIterable, DatabaseValueConvertible {
        case queued
        case inProgress = "in_progress"
        case passed
        case failed
        case needsRevision = "needs_revision"
        case cancelled
    }

    package init(
        id: UUID = UUID(),
        projectId: UUID,
        featureId: UUID? = nil,
        agentType: AgentType,
        title: String,
        description: String,
        priority: Int = 0,
        status: Status = .queued,
        result: String? = nil,
        errorMessage: String? = nil,
        retryCount: Int = 0,
        maxRetries: Int = 3,
        sessionId: String? = nil,
        branchName: String? = nil,
        prNumber: Int? = nil,
        costUSD: Double? = nil,
        durationMs: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.featureId = featureId
        self.agentType = agentType
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.result = result
        self.errorMessage = errorMessage
        self.retryCount = retryCount
        self.maxRetries = maxRetries
        self.sessionId = sessionId
        self.branchName = branchName
        self.prNumber = prNumber
        self.costUSD = costUSD
        self.durationMs = durationMs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

// MARK: - Persistence

extension AgentTask: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "agentTask"

    static let project = belongsTo(Project.self)
    static let feature = belongsTo(Feature.self)
    static let reviews = hasMany(Review.self)
    static let agentLogs = hasMany(AgentLog.self)
    static let dependsOn = hasMany(
        TaskDependency.self,
        using: TaskDependency.ForeignKeys.task
    )
    static let dependedOnBy = hasMany(
        TaskDependency.self,
        using: TaskDependency.ForeignKeys.dependsOn
    )

    var project: QueryInterfaceRequest<Project> {
        request(for: AgentTask.project)
    }

    var reviews: QueryInterfaceRequest<Review> {
        request(for: AgentTask.reviews)
    }
}
