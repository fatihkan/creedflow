import Foundation
import GRDB

struct AgentLog: Codable, Identifiable, Equatable {
    var id: UUID
    var taskId: UUID
    var agentType: AgentTask.AgentType
    var level: Level
    var message: String
    var metadata: String?
    var createdAt: Date

    enum Level: String, Codable, CaseIterable, DatabaseValueConvertible {
        case debug
        case info
        case warning
        case error
    }

    init(
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
    static let databaseTableName = "agentLog"

    static let task = belongsTo(AgentTask.self)
}
