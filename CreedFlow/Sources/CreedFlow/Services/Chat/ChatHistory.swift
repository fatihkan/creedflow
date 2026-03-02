import Foundation
import GRDB

/// Manages chat message persistence and context building for project conversations.
actor ChatHistory {
    private let dbQueue: DatabaseQueue
    private var contextCache: [UUID: CachedContext] = [:]

    struct CachedContext {
        let projectSummary: String
        let historySummary: String?
        let lastMessageCount: Int
        let createdAt: Date
    }

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Message CRUD

    func loadMessages(for projectId: UUID) throws -> [ProjectMessage] {
        try dbQueue.read { db in
            try ProjectMessage
                .filter(Column("projectId") == projectId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func saveMessage(_ message: ProjectMessage) throws {
        try dbQueue.write { db in
            var msg = message
            try msg.insert(db)
        }
    }

    func updateMessageMetadata(id: UUID, metadata: String) throws {
        try dbQueue.write { db in
            guard var msg = try ProjectMessage.fetchOne(db, id: id) else { return }
            msg.metadata = metadata
            try msg.update(db)
        }
    }

    func messageCount(for projectId: UUID) throws -> Int {
        try dbQueue.read { db in
            try ProjectMessage
                .filter(Column("projectId") == projectId)
                .fetchCount(db)
        }
    }

    // MARK: - Context Building

    /// Builds the full prompt context for the AI, including project info, history, and the new message.
    func buildContext(for projectId: UUID, newMessage: String) throws -> String {
        let project = try dbQueue.read { db in
            try Project.fetchOne(db, id: projectId)
        }
        guard let project else { return newMessage }

        let messages = try loadMessages(for: projectId)
        let contextLimit = 30

        // Build project summary (cached)
        let projectSummary: String
        if let cached = contextCache[projectId] {
            projectSummary = cached.projectSummary
        } else {
            projectSummary = buildProjectSummary(project)
        }

        // Build history summary for old messages if needed
        var historySummary: String?
        if messages.count > contextLimit {
            if let cached = contextCache[projectId], cached.lastMessageCount == messages.count - 1 {
                historySummary = cached.historySummary
            } else {
                let oldMessages = Array(messages.prefix(messages.count - contextLimit))
                historySummary = summarizeMessages(oldMessages)
            }
        }

        // Cache for next call
        contextCache[projectId] = CachedContext(
            projectSummary: projectSummary,
            historySummary: historySummary,
            lastMessageCount: messages.count,
            createdAt: Date()
        )

        // Build the full prompt
        var parts: [String] = []

        parts.append("""
        You are a project planning assistant for CreedFlow.
        Help the user plan features and tasks for their project.
        When the user is ready, propose tasks by outputting a JSON block in this format:

        ```json
        {"type":"taskProposal","features":[{"name":"Feature Name","description":"...","priority":1,"tasks":[{"title":"Task title","description":"...","agentType":"coder","priority":1,"dependsOn":[],"acceptanceCriteria":[],"filesToCreate":[],"estimatedComplexity":"medium"}]}]}
        ```

        Available agent types: analyzer, coder, reviewer, tester, devops, monitor, contentWriter, designer, imageGenerator, videoEditor, publisher.
        Only output the JSON block when the user explicitly approves or asks you to create the tasks.
        """)

        parts.append("")
        parts.append("## Project")
        parts.append(projectSummary)

        if let summary = historySummary {
            parts.append("")
            parts.append("## Previous Discussion Summary")
            parts.append(summary)
        }

        // Recent conversation (last N messages)
        let recentMessages = messages.count > contextLimit
            ? Array(messages.suffix(contextLimit))
            : messages
        if !recentMessages.isEmpty {
            parts.append("")
            parts.append("## Recent Conversation")
            for msg in recentMessages {
                let roleLabel = msg.role == .user ? "User" : (msg.role == .assistant ? "Assistant" : "System")
                parts.append("\(roleLabel): \(msg.content)")
            }
        }

        parts.append("")
        parts.append("User: \(newMessage)")

        return parts.joined(separator: "\n")
    }

    func invalidateCache(for projectId: UUID) {
        contextCache.removeValue(forKey: projectId)
    }

    // MARK: - Helpers

    private func buildProjectSummary(_ project: Project) -> String {
        var parts: [String] = []
        parts.append("Name: \(project.name)")
        parts.append("Type: \(project.projectType.rawValue)")
        if !project.techStack.isEmpty {
            parts.append("Tech Stack: \(project.techStack)")
        }
        parts.append("Description: \(project.description)")
        return parts.joined(separator: " | ")
    }

    private func summarizeMessages(_ messages: [ProjectMessage]) -> String {
        let lines = messages.map { msg -> String in
            let roleLabel = msg.role == .user ? "User" : (msg.role == .assistant ? "AI" : "System")
            let truncated = msg.content.prefix(100)
            return "- \(roleLabel): \(truncated)\(msg.content.count > 100 ? "..." : "")"
        }
        return "Earlier conversation (\(messages.count) messages):\n" + lines.joined(separator: "\n")
    }
}
