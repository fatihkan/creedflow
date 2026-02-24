import Foundation
import GRDB

/// Junction table for task dependencies (replaces UUID[] from PostgreSQL design)
struct TaskDependency: Codable, Equatable {
    var taskId: UUID
    var dependsOnTaskId: UUID

    init(taskId: UUID, dependsOnTaskId: UUID) {
        self.taskId = taskId
        self.dependsOnTaskId = dependsOnTaskId
    }
}

// MARK: - Persistence

extension TaskDependency: FetchableRecord, PersistableRecord {
    static let databaseTableName = "taskDependency"

    enum ForeignKeys {
        static let task = ForeignKey(["taskId"])
        static let dependsOn = ForeignKey(["dependsOnTaskId"])
    }

    static let task = belongsTo(AgentTask.self, using: ForeignKeys.task)
    static let dependsOnTask = belongsTo(AgentTask.self, using: ForeignKeys.dependsOn)
}
