import Foundation
import GRDB

package struct AgentLog: Codable, Identifiable, Equatable {
    package var id: UUID
    package var taskId: UUID
    package var agentType: AgentTask.AgentType
    package var level: Level
    package var message: String
    package var metadata: String?
    package var createdAt: Date

    package enum Level: String, Codable, CaseIterable, DatabaseValueConvertible {
        case debug
        case info
        case warning
        case error
    }

    package init(
        id: UUID = UUID(),
        taskId: UUID,
        agentType: AgentTask.AgentType,
        level: Level = .info,
        message: String,
        metadata: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.agentType = agentType
        self.level = level
        self.message = message
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

// MARK: - Persistence

extension AgentLog: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "agentLog"

    static let task = belongsTo(AgentTask.self)
}
