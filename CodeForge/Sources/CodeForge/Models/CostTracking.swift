import Foundation
import GRDB

package struct CostTracking: Codable, Identifiable, Equatable {
    package var id: UUID
    package var projectId: UUID
    package var taskId: UUID?
    package var agentType: AgentTask.AgentType
    package var inputTokens: Int
    package var outputTokens: Int
    package var costUSD: Double
    package var model: String
    package var sessionId: String?
    package var backend: String?
    package var createdAt: Date

    package init(
        id: UUID = UUID(),
        projectId: UUID,
        taskId: UUID? = nil,
        agentType: AgentTask.AgentType,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        costUSD: Double = 0,
        model: String = "claude-sonnet-4-20250514",
        sessionId: String? = nil,
        backend: String? = nil,
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
        self.backend = backend
        self.createdAt = createdAt
    }
}

// MARK: - Persistence

extension CostTracking: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "costTracking"

    static let project = belongsTo(Project.self)
    static let task = belongsTo(AgentTask.self)
}
