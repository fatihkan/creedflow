import Foundation
import GRDB

/// High-level runner that executes an AgentTask on any CLIBackend.
/// Replaces ClaudeAgentRunner's role in the Orchestrator dispatch loop.
/// Maintains the same @Observable pattern for UI display of live output.
@Observable
final class MultiBackendRunner {
    private let backend: any CLIBackend
    private let dbQueue: DatabaseQueue

    /// Live output lines for UI display (same type as ClaudeAgentRunner.OutputLine)
    private(set) var liveOutput: [OutputLine] = []
    private(set) var isRunning = false
    private(set) var backendType: CLIBackendType

    struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let type: LineType
        let timestamp: Date

        enum LineType {
            case text
            case toolUse
            case error
            case system
        }
    }

    init(backend: any CLIBackend, dbQueue: DatabaseQueue) {
        self.backend = backend
        self.dbQueue = dbQueue
        self.backendType = backend.backendType
    }

    /// Execute an agent task with full lifecycle management.
    /// - Parameter promptOverride: If provided, replaces the agent's default prompt (used by PromptRecommender / ChainExecutor).
    func execute(task: AgentTask, agent: any AgentProtocol, workingDirectory: String = "", promptOverride: String? = nil) async throws -> AgentResult {
        isRunning = true
        liveOutput = []
        defer { isRunning = false }

        addOutputLine("Starting \(agent.agentType.rawValue) agent via \(backendType.rawValue) for: \(task.title)", type: .system)

        // Generate MCP config if agent needs MCP servers (Claude only)
        var mcpConfigPath: String?
        if backendType == .claude, let serverNames = agent.mcpServers, !serverNames.isEmpty {
            let generator = MCPConfigGenerator(dbQueue: dbQueue)
            mcpConfigPath = try generator.generateConfig(serverNames: serverNames)
            if let path = mcpConfigPath {
                addOutputLine("MCP config: \(path)", type: .system)
            }
        }
        defer {
            if let path = mcpConfigPath {
                MCPConfigGenerator.cleanup(path: path)
            }
        }

        // Build backend-neutral task input
        let input = CLITaskInput(
            prompt: promptOverride ?? agent.buildPrompt(for: task),
            systemPrompt: agent.systemPrompt,
            workingDirectory: workingDirectory.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : workingDirectory,
            allowedTools: backendType == .claude ? agent.allowedTools : nil,
            maxBudgetUSD: backendType == .claude ? agent.maxBudgetUSD : nil,
            timeoutSeconds: agent.timeoutSeconds,
            mcpConfigPath: mcpConfigPath,
            jsonSchema: backendType == .claude ? agent.jsonSchema : nil
        )

        let (processId, stream) = await backend.execute(input)

        var sessionId: String?
        var capturedModel: String?
        var resultText: String?
        var totalCost: Double?
        var durationMs: Int?
        var inputTokens = 0
        var outputTokens = 0

        // Consume stream with timeout
        let timeoutSeconds = agent.timeoutSeconds
        let backendRef = backend

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Stream consumer task
                group.addTask {
                    for try await event in stream {
                        switch event {
                        case .text(let text):
                            await MainActor.run { [self] in self.addOutputLine(text, type: .text) }

                        case .toolUse(let name):
                            await MainActor.run { [self] in self.addOutputLine("Tool: \(name)", type: .toolUse) }

                        case .system(let sid, let model):
                            await MainActor.run { [self] in
                                sessionId = sid
                                capturedModel = model
                                if let sid {
                                    self.addOutputLine("Session: \(sid)", type: .system)
                                }
                            }

                        case .result(let res):
                            await MainActor.run { [self] in
                                resultText = res.output
                                totalCost = res.costUSD
                                durationMs = res.durationMs
                                inputTokens = res.inputTokens
                                outputTokens = res.outputTokens
                                if let model = res.model {
                                    capturedModel = model
                                }
                                if let sid = res.sessionId {
                                    sessionId = sid
                                }

                                if res.isError {
                                    self.addOutputLine("Error: \(res.output ?? "unknown")", type: .error)
                                } else {
                                    self.addOutputLine("Completed successfully", type: .system)
                                }
                            }

                        case .error(let msg):
                            await MainActor.run { [self] in self.addOutputLine("Error: \(msg)", type: .error) }
                        }
                    }
                }

                // Timeout task
                group.addTask {
                    try await Task.sleep(for: .seconds(timeoutSeconds))
                    await backendRef.cancel(processId)
                    throw ClaudeError.timeout
                }

                // Wait for stream to finish, then cancel timeout
                try await group.next()
                group.cancelAll()
            }
        } catch is CancellationError {
            // TaskGroup cancellation from group.cancelAll() — not a real error
        } catch let error as ClaudeError where error.localizedDescription.contains("timed out") {
            let errorMsg = "Task timed out after \(timeoutSeconds)s"
            addOutputLine("Error: \(errorMsg)", type: .error)

            try await dbQueue.write { db in
                var updatedTask = task
                updatedTask.status = .failed
                updatedTask.errorMessage = errorMsg
                updatedTask.backend = self.backendType.rawValue
                updatedTask.updatedAt = Date()
                updatedTask.completedAt = Date()
                try updatedTask.update(db)
            }

            throw ClaudeError.timeout
        } catch {
            let errorMsg = error.localizedDescription
            addOutputLine("Error: \(errorMsg)", type: .error)

            try await dbQueue.write { db in
                var updatedTask = task
                updatedTask.status = .failed
                updatedTask.errorMessage = errorMsg
                updatedTask.backend = self.backendType.rawValue
                updatedTask.updatedAt = Date()
                updatedTask.completedAt = Date()
                try updatedTask.update(db)
            }

            throw error
        }

        // Capture final values for Sendable closure safety
        let finalSessionId = sessionId
        let finalCapturedModel = capturedModel
        let finalResultText = resultText
        let finalTotalCost = totalCost
        let finalDurationMs = durationMs
        let finalInputTokens = inputTokens
        let finalOutputTokens = outputTokens
        let finalBackendType = backendType

        let agentResult = AgentResult(
            sessionId: finalSessionId,
            output: finalResultText,
            costUSD: finalTotalCost,
            durationMs: finalDurationMs,
            inputTokens: finalInputTokens,
            outputTokens: finalOutputTokens
        )

        // Update task with results
        try await dbQueue.write { db in
            var updatedTask = task
            updatedTask.status = .passed
            updatedTask.result = finalResultText
            updatedTask.sessionId = finalSessionId
            updatedTask.costUSD = finalTotalCost
            updatedTask.durationMs = finalDurationMs.map(Int64.init)
            updatedTask.backend = finalBackendType.rawValue
            updatedTask.updatedAt = Date()
            updatedTask.completedAt = Date()
            try updatedTask.update(db)
        }

        // Record cost
        if let cost = finalTotalCost, cost > 0 {
            try await dbQueue.write { db in
                let costRecord = CostTracking(
                    projectId: task.projectId,
                    taskId: task.id,
                    agentType: task.agentType,
                    inputTokens: finalInputTokens,
                    outputTokens: finalOutputTokens,
                    costUSD: cost,
                    model: finalCapturedModel ?? finalBackendType.rawValue,
                    sessionId: finalSessionId,
                    backend: finalBackendType.rawValue
                )
                try costRecord.insert(db)
            }
        }

        return agentResult
    }

    private func addOutputLine(_ text: String, type: OutputLine.LineType) {
        liveOutput.append(OutputLine(text: text, type: type, timestamp: Date()))
    }
}
