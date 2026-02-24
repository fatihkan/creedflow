import Foundation
import GRDB

struct PromptVersion: Codable, Identifiable, Equatable {
    var id: UUID
    var promptId: UUID
    var version: Int
    var title: String
    var content: String
    var changeNote: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        promptId: UUID,
        version: Int,
        title: String,
        content: String,
        changeNote: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.promptId = promptId
        self.version = version
        self.title = title
        self.content = content
        self.changeNote = changeNote
        self.createdAt = createdAt
    }
}

// MARK: - Persistence

extension PromptVersion: FetchableRecord, PersistableRecord {
    static let databaseTableName = "promptVersion"

    static let prompt = belongsTo(Prompt.self)

    var prompt: QueryInterfaceRequest<Prompt> {
        request(for: PromptVersion.prompt)
    }
}
