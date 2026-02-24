import Foundation
import GRDB

struct Review: Codable, Identifiable, Equatable {
    var id: UUID
    var taskId: UUID
    var score: Double
    var verdict: Verdict
    var summary: String
    var issues: String?
    var suggestions: String?
    var securityNotes: String?
    var sessionId: String?
    var costUSD: Double?
    var isApproved: Bool
    var createdAt: Date

    enum Verdict: String, Codable, CaseIterable, DatabaseValueConvertible {
        case pass       // score >= 7.0
        case needsRevision  // 5.0 - 6.9
        case fail       // < 5.0
    }

    init(
        id: UUID = UUID(),
        taskId: UUID,
        score: Double,
        verdict: Verdict,
        summary: String,
        issues: String? = nil,
        suggestions: String? = nil,
        securityNotes: String? = nil,
        sessionId: String? = nil,
        costUSD: Double? = nil,
        isApproved: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.score = score
        self.verdict = verdict
        self.summary = summary
        self.issues = issues
        self.suggestions = suggestions
        self.securityNotes = securityNotes
        self.sessionId = sessionId
        self.costUSD = costUSD
        self.isApproved = isApproved
        self.createdAt = createdAt
    }
}

// MARK: - Persistence

extension Review: FetchableRecord, PersistableRecord {
    static let databaseTableName = "review"

    static let task = belongsTo(AgentTask.self)

    var task: QueryInterfaceRequest<AgentTask> {
        request(for: Review.task)
    }
}
