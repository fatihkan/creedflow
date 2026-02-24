import Foundation
import GRDB

struct PromptUsage: Codable, Identifiable, Equatable {
    var id: UUID
    var promptId: UUID
    var projectId: UUID?
    var taskId: UUID?
    var outcome: Outcome?
    var reviewScore: Double?
    var usedAt: Date

    enum Outcome: String, Codable, DatabaseValueConvertible {
        case completed
        case failed
    }

    init(
        id: UUID = UUID(),
        promptId: UUID,
        projectId: UUID? = nil,
        taskId: UUID? = nil,
        outcome: Outcome? = nil,
        reviewScore: Double? = nil,
        usedAt: Date = Date()
    ) {
        self.id = id
        self.promptId = promptId
        self.projectId = projectId
        self.taskId = taskId
        self.outcome = outcome
        self.reviewScore = reviewScore
        self.usedAt = usedAt
    }
}

// MARK: - Persistence

extension PromptUsage: FetchableRecord, PersistableRecord {
    static let databaseTableName = "promptUsage"

    static let prompt = belongsTo(Prompt.self)

    var prompt: QueryInterfaceRequest<Prompt> {
        request(for: PromptUsage.prompt)
    }
}
