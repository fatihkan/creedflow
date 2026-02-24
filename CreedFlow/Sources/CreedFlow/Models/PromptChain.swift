import Foundation
import GRDB

struct PromptChain: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var description: String
    var category: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        category: String = "general",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension PromptChain: FetchableRecord, PersistableRecord {
    static let databaseTableName = "promptChain"

    static let steps = hasMany(PromptChainStep.self, using: PromptChainStep.ForeignKeys.chain)
    static let usages = hasMany(PromptUsage.self)

    var steps: QueryInterfaceRequest<PromptChainStep> {
        request(for: PromptChain.steps)
    }

    var usages: QueryInterfaceRequest<PromptUsage> {
        request(for: PromptChain.usages)
    }
}
