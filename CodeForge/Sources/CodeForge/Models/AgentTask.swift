import Foundation
import GRDB

/// Named "AgentTask" to avoid collision with Swift.Task
struct AgentTask: Codable, Identifiable, Equatable {
    var id: UUID
    var projectId: UUID
    var featureId: UUID?
    var agentType: AgentType
    var title: String
    var description: String
    var priority: Int
    var status: Status
    var result: String?
    var errorMessage: String?
    var retryCount: Int
    var maxRetries: Int
    var sessionId: String?
    var branchName: String?
    var prNumber: Int?
    var costUSD: Double?
    var durationMs: Int64?
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var completedAt: Date?

    enum AgentType: String, Codable, CaseIterable, DatabaseValueConvertible {
        case analyzer
        case coder
        case reviewer
        case tester
        case devops
        case monitor
    }

    enum Status: String, Codable, CaseIterable, DatabaseValueConvertible {
        case queued
        case inProgress = "in_progress"
        case passed
        case failed
        case needsRevision = "needs_revision"
        case cancelled
    }

    init(
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
    static let databaseTableName = "agentTask"

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
