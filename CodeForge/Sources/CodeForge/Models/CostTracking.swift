import Foundation
import GRDB

struct CostTracking: Codable, Identifiable, Equatable {
    var id: UUID
    var projectId: UUID
    var taskId: UUID?
    var agentType: AgentTask.AgentType
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double
    var model: String
    var sessionId: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        projectId: UUID,
        taskId: UUID? = nil,
        agentType: AgentTask.AgentType,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        costUSD: Double = 0,
        model: String = "claude-sonnet-4-20250514",
        sessionId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.agentType = agentType
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.model = model
        self.sessionId = sessionId
        self.createdAt = createdAt
    }
}

// MARK: - Persistence

extension CostTracking: FetchableRecord, PersistableRecord {
    static let databaseTableName = "costTracking"

    static let project = belongsTo(Project.self)
    static let task = belongsTo(AgentTask.self)
}
