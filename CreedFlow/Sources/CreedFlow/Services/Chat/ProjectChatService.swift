import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "com.creedflow", category: "ProjectChatService")

/// Manages chat conversations for a project — handles sending messages,
/// streaming AI responses, and task proposal approval.
@Observable
final class ProjectChatService {
    private(set) var messages: [ProjectMessage] = []
    private(set) var isStreaming = false
    private(set) var streamingContent = ""
    private(set) var activeBackend: CLIBackendType?
    var error: String?

    private let history: ChatHistory
    private let backendRouter: BackendRouter
    private let dbQueue: DatabaseQueue
    private var projectId: UUID?
    private var project: Project?
    private var observationTask: Task<Void, Never>?
    private var activeProcessId: UUID?
    private var activeBackendRef: (any CLIBackend)?

    init(dbQueue: DatabaseQueue, backendRouter: BackendRouter) {
        self.dbQueue = dbQueue
        self.backendRouter = backendRouter
        self.history = ChatHistory(dbQueue: dbQueue)
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Binding

    /// Bind to a project — loads messages and starts observing changes.
    func bind(to projectId: UUID) {
        guard self.projectId != projectId else { return }
        self.projectId = projectId
        observationTask?.cancel()

        // Load project
        Task {
            self.project = try? await dbQueue.read { db in
                try Project.fetchOne(db, id: projectId)
            }
        }

        // Start observation
        let observation = ValueObservation.tracking { db in
            try ProjectMessage
                .filter(Column("projectId") == projectId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }

        let db = dbQueue
        observationTask = Task { [weak self] in
            do {
                for try await msgs in observation.values(in: db) {
                    await MainActor.run {
                        self?.messages = msgs
                    }
                }
            } catch {
                logger.error("Observation error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Send Message

    /// Send a user message and get an AI response.
    @MainActor
    func send(_ text: String) async {
        guard let projectId else {
            error = "No project bound"
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        error = nil

        // Save user message
        let userMessage = ProjectMessage(
            projectId: projectId,
            role: .user,
            content: trimmed
        )
        do {
            try await history.saveMessage(userMessage)
        } catch {
            self.error = "Failed to save message: \(error.localizedDescription)"
            return
        }

        // Select backend
        guard let backend = await backendRouter.selectBackend(preferences: .anyBackend) else {
            self.error = "No AI backend available. Enable at least one backend in Settings."
            return
        }

        isStreaming = true
        streamingContent = ""
        activeBackend = backend.backendType

        let startTime = Date()

        do {
            // Build context prompt
            let prompt = try await history.buildContext(for: projectId, newMessage: trimmed)

            let input = CLITaskInput(
                prompt: prompt,
                systemPrompt: nil,
                workingDirectory: project?.directoryPath ?? FileManager.default.homeDirectoryForCurrentUser.path,
                allowedTools: nil,
                maxBudgetUSD: nil,
                timeoutSeconds: 300,
                mcpConfigPath: nil,
                jsonSchema: nil
            )

            let (processId, stream) = await backend.execute(input)
            activeProcessId = processId
            activeBackendRef = backend

            var resultText: String?
            var totalCost: Double?
            var durationMs: Int64?

            for try await event in stream {
                switch event {
                case .text(let text):
                    streamingContent += text
                case .result(let res):
                    if let output = res.output {
                        resultText = output
                    }
                    totalCost = res.costUSD
                    if let ms = res.durationMs {
                        durationMs = Int64(ms)
                    }
                case .error(let msg):
                    logger.warning("Stream error: \(msg)")
                case .toolUse, .system:
                    break
                }
            }

            // Use result text if available, otherwise use accumulated streaming content
            let finalContent = resultText ?? streamingContent
            guard !finalContent.isEmpty else {
                self.error = "AI returned empty response"
                isStreaming = false
                activeBackend = nil
                return
            }

            // Check for task proposal in the response
            let metadata = extractTaskProposal(from: finalContent)

            let elapsed = Int64(Date().timeIntervalSince(startTime) * 1000)

            // Save assistant message
            let assistantMessage = ProjectMessage(
                projectId: projectId,
                role: .assistant,
                content: finalContent,
                backend: backend.backendType.rawValue,
                costUSD: totalCost,
                durationMs: durationMs ?? elapsed,
                metadata: metadata
            )
            try await history.saveMessage(assistantMessage)

        } catch {
            self.error = "AI error: \(error.localizedDescription)"
            logger.error("Chat error: \(error.localizedDescription)")
        }

        isStreaming = false
        streamingContent = ""
        activeBackend = nil
        activeProcessId = nil
        activeBackendRef = nil
    }

    // MARK: - Cancel

    func cancel() {
        guard let processId = activeProcessId, let backend = activeBackendRef else { return }
        Task {
            await backend.cancel(processId)
        }
        isStreaming = false
        streamingContent = ""
        activeBackend = nil
        activeProcessId = nil
        activeBackendRef = nil
    }

    // MARK: - Task Proposal

    /// Approve a task proposal — creates features and tasks in the DB.
    func approveProposal(messageId: UUID) async {
        guard let message = messages.first(where: { $0.id == messageId }),
              let metadataStr = message.metadata,
              let data = metadataStr.data(using: .utf8) else {
            error = "No proposal found"
            return
        }

        do {
            let proposal = try JSONDecoder().decode(TaskProposal.self, from: data)
            guard proposal.status == "pending" else {
                error = "Proposal already \(proposal.status)"
                return
            }

            guard let projectId else { return }

            // Build title → UUID mapping
            var titleToTaskId: [String: UUID] = [:]
            for feature in proposal.features {
                for task in feature.tasks {
                    if titleToTaskId[task.title] == nil {
                        titleToTaskId[task.title] = UUID()
                    }
                }
            }

            // Create features and tasks in DB
            try await dbQueue.write { db in
                for featureOutput in proposal.features {
                    let feature = Feature(
                        projectId: projectId,
                        name: featureOutput.name,
                        description: featureOutput.description,
                        priority: featureOutput.priority
                    )
                    try feature.insert(db)

                    for taskOutput in featureOutput.tasks {
                        guard let pregenId = titleToTaskId[taskOutput.title] else { continue }
                        let agentType = Self.parseAgentType(taskOutput.agentType)

                        var descParts = [taskOutput.description]
                        if let criteria = taskOutput.acceptanceCriteria, !criteria.isEmpty {
                            descParts.append("\n\nAcceptance Criteria:\n" + criteria.map { "- \($0)" }.joined(separator: "\n"))
                        }
                        if let files = taskOutput.filesToCreate, !files.isEmpty {
                            descParts.append("\n\nFiles to create:\n" + files.map { "- \($0)" }.joined(separator: "\n"))
                        }

                        let newTask = AgentTask(
                            id: pregenId,
                            projectId: projectId,
                            featureId: feature.id,
                            agentType: agentType,
                            title: taskOutput.title,
                            description: descParts.joined(),
                            priority: taskOutput.priority
                        )
                        try newTask.insert(db)
                    }
                }

                // Create dependency edges
                for featureOutput in proposal.features {
                    for taskOutput in featureOutput.tasks {
                        guard let deps = taskOutput.dependsOn, !deps.isEmpty else { continue }
                        guard let taskId = titleToTaskId[taskOutput.title] else { continue }
                        for depTitle in deps {
                            if let depId = titleToTaskId[depTitle] {
                                let dep = TaskDependency(taskId: taskId, dependsOnTaskId: depId)
                                try dep.insert(db)
                            }
                        }
                    }
                }

                // Update project status
                if var project = try Project.fetchOne(db, id: projectId) {
                    project.status = .inProgress
                    project.updatedAt = Date()
                    try project.update(db)
                }
            }

            // Update proposal status to approved
            var updatedProposal = proposal
            updatedProposal.status = "approved"
            let updatedJson = try JSONEncoder().encode(updatedProposal)
            try await history.updateMessageMetadata(id: messageId, metadata: String(data: updatedJson, encoding: .utf8) ?? "")

        } catch {
            self.error = "Failed to create tasks: \(error.localizedDescription)"
            logger.error("Approve error: \(error.localizedDescription)")
        }
    }

    /// Reject a task proposal.
    func rejectProposal(messageId: UUID) async {
        guard let message = messages.first(where: { $0.id == messageId }),
              let metadataStr = message.metadata,
              let data = metadataStr.data(using: .utf8) else { return }

        do {
            var proposal = try JSONDecoder().decode(TaskProposal.self, from: data)
            proposal.status = "rejected"
            let updatedJson = try JSONEncoder().encode(proposal)
            try await history.updateMessageMetadata(id: messageId, metadata: String(data: updatedJson, encoding: .utf8) ?? "")
        } catch {
            self.error = "Failed to reject proposal: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func extractTaskProposal(from content: String) -> String? {
        // Look for JSON block with taskProposal
        guard let jsonRange = content.range(of: "```json"),
              let endRange = content.range(of: "```", range: jsonRange.upperBound..<content.endIndex) else {
            // Try direct JSON detection
            if content.contains("\"taskProposal\"") || content.contains("\"type\":\"taskProposal\"") {
                if let start = content.firstIndex(of: "{"),
                   let jsonData = extractJSONObject(from: String(content[start...])) {
                    return jsonData
                }
            }
            return nil
        }

        let jsonStr = String(content[jsonRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate it's a task proposal
        guard jsonStr.contains("taskProposal") || jsonStr.contains("features") else { return nil }

        // Wrap with status if not present
        if let data = jsonStr.data(using: .utf8),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if json["status"] == nil {
                json["status"] = "pending"
            }
            if json["type"] == nil {
                json["type"] = "taskProposal"
            }
            if let result = try? JSONSerialization.data(withJSONObject: json),
               let str = String(data: result, encoding: .utf8) {
                return str
            }
        }

        return jsonStr
    }

    private func extractJSONObject(from text: String) -> String? {
        var depth = 0
        var start: String.Index?
        for (i, char) in text.enumerated() {
            let idx = text.index(text.startIndex, offsetBy: i)
            if char == "{" {
                if depth == 0 { start = idx }
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0, let s = start {
                    return String(text[s...idx])
                }
            }
        }
        return nil
    }

    private static func parseAgentType(_ raw: String) -> AgentTask.AgentType {
        switch raw.lowercased() {
        case "coder": return .coder
        case "devops": return .devops
        case "tester": return .tester
        case "reviewer": return .reviewer
        case "contentwriter": return .contentWriter
        case "designer": return .designer
        case "imagegenerator": return .imageGenerator
        case "videoeditor": return .videoEditor
        case "publisher": return .publisher
        case "analyzer": return .analyzer
        case "monitor": return .monitor
        default: return .coder
        }
    }
}

// MARK: - Task Proposal Model

struct TaskProposal: Codable {
    var type: String
    var status: String
    var features: [FeatureProposal]

    struct FeatureProposal: Codable {
        let name: String
        let description: String
        let priority: Int
        let tasks: [TaskProposalItem]
    }

    struct TaskProposalItem: Codable {
        let title: String
        let description: String
        let agentType: String
        let priority: Int
        let dependsOn: [String]?
        let acceptanceCriteria: [String]?
        let filesToCreate: [String]?
        let estimatedComplexity: String?
    }
}
