import Foundation
import GRDB

package struct TaskComment: Codable, Identifiable, Equatable {
    package var id: UUID
    package var taskId: UUID
    package var content: String
    package var author: Author
    package var createdAt: Date

    package enum Author: String, Codable, DatabaseValueConvertible {
        case user
        case system
    }

    package init(
        id: UUID = UUID(),
        taskId: UUID,
        content: String,
        author: Author = .user,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.content = content
        self.author = author
        self.createdAt = createdAt
    }
}

// MARK: - Persistence

extension TaskComment: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "taskComment"
}
