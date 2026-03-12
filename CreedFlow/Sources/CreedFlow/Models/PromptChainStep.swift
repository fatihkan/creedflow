import Foundation
import GRDB

struct PromptChainStep: Codable, Identifiable, Equatable {
    var id: UUID
    var chainId: UUID
    var promptId: UUID
    var stepOrder: Int
    var transitionNote: String?
    var condition: String?
    var onFailStepOrder: Int?

    init(
        id: UUID = UUID(),
        chainId: UUID,
        promptId: UUID,
        stepOrder: Int,
        transitionNote: String? = nil,
        condition: String? = nil,
        onFailStepOrder: Int? = nil
    ) {
        self.id = id
        self.chainId = chainId
        self.promptId = promptId
        self.stepOrder = stepOrder
        self.transitionNote = transitionNote
        self.condition = condition
        self.onFailStepOrder = onFailStepOrder
    }
}

// MARK: - Persistence

extension PromptChainStep: FetchableRecord, PersistableRecord {
    static let databaseTableName = "promptChainStep"

    enum ForeignKeys {
        static let chain = ForeignKey(["chainId"])
        static let prompt = ForeignKey(["promptId"])
    }

    static let chain = belongsTo(PromptChain.self, using: ForeignKeys.chain)
    static let prompt = belongsTo(Prompt.self, using: ForeignKeys.prompt)

    var chain: QueryInterfaceRequest<PromptChain> {
        request(for: PromptChainStep.chain)
    }

    var prompt: QueryInterfaceRequest<Prompt> {
        request(for: PromptChainStep.prompt)
    }
}
