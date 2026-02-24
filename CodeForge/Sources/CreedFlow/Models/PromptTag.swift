import Foundation
import GRDB

struct PromptTag: Codable, Equatable {
    var promptId: UUID
    var tag: String

    init(promptId: UUID, tag: String) {
        self.promptId = promptId
        self.tag = tag
    }
}

// MARK: - Persistence

extension PromptTag: FetchableRecord, PersistableRecord {
    static let databaseTableName = "promptTag"

    static let prompt = belongsTo(Prompt.self)

    var prompt: QueryInterfaceRequest<Prompt> {
        request(for: PromptTag.prompt)
    }
}
