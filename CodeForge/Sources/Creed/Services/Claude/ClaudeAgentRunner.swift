import Foundation
import GRDB

/// High-level runner: takes an AgentTask, builds a ClaudeInvocation from the
/// agent's configuration, spawns the process, collects results, and updates the DB.
@Observable
final class ClaudeAgentRunner {
    private let processManager: ClaudeProcessManager
    private let dbQueue: DatabaseQueue

    /// Live output lines for UI display
    private(set) var liveOutput: [OutputLine] = []
    private(set) var isRunning = false

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

    init(processManager: ClaudeProcessManager, dbQueue: DatabaseQueue) {
        self.processManager = processManager
        self.dbQueue = dbQueue
    }

    /// Execute an agent task with full lifecycle management
    func execute(task: AgentTask, agent: any AgentProtocol, workingDirectory: String = "") async throws -> AgentResult {
        isRunning = true
        liveOutput = []
        defer { isRunning = false }

        // Task is already marked in-progress by TaskQueue.dequeue() — no duplicate write needed

        addOutputLine("Starting \(agent.agentType.rawValue) agent for: \(task.title)", type: .system)

        // Generate MCP config if agent needs MCP servers
        var mcpConfigPath: String?
        if let serverNames = agent.mcpServers, !serverNames.isEmpty {
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

        // Build invocation from agent config, override working directory and MCP config
        var invocation = agent.buildInvocation(for: task)
        if !workingDirectory.isEmpty || mcpConfigPath != nil {
            invocation = invocation.with(
                workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory,
                mcpConfigPath: mcpConfigPath
            )
        }
        let (processId, stream) = await processManager.run(invocation)

        var sessionId: String?
        var capturedModel: String?
        var resultText: String?
        var totalCost: Double?
        var durationMs: Int?
        var inputTokens = 0
        var outputTokens = 0

        // Consume stream with timeout — if timeout fires first, it cancels the process
        // and throws ClaudeError.timeout directly (not lost in a detached Task)
        let timeoutSeconds = agent.timeoutSeconds
        let pmRef = processManager

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Stream consumer task
                group.addTask {
                    for try await event in stream {
                        switch event {
                        case .system(let sysEvent):
                            await MainActor.run { [self] in
                                sessionId = sysEvent.sessionId
                                capturedModel = sysEvent.model
                                self.addOutputLine("Session: \(sysEvent.sessionId)", type: .system)
                            }

                        case .assistant(let assistantEvent):
                            for content in assistantEvent.message.content {
                                if let text = content.text {
                                    await MainActor.run { [self] in self.addOutputLine(text, type: .text) }
                                }
                                if let toolName = content.name {
                                    await MainActor.run { [self] in self.addOutputLine("Tool: \(toolName)", type: .toolUse) }
                                }
                            }

                        case .result(let res):
                            await MainActor.run { [self] in
                                resultText = res.result
                                totalCost = res.totalCostUsd ?? res.cost?.totalUsd
                                durationMs = res.durationMs
                                inputTokens = res.cost?.inputTokens ?? 0
                                outputTokens = res.cost?.outputTokens ?? 0

                                if res.isError == true {
                                    self.addOutputLine("Error: \(res.result ?? "unknown")", type: .error)
                                } else {
                                    self.addOutputLine("Completed successfully", type: .system)
                                }
                            }

                        case .ignored, .unknown:
                            break
                        }
                    }
                }

                // Timeout task
                group.addTask {
                    try await Task.sleep(for: .seconds(timeoutSeconds))
                    await pmRef.cancel(processId)
                    throw ClaudeError.timeout
                }

                // Wait for stream to finish (first task), then cancel timeout
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
                    model: finalCapturedModel ?? "claude-sonnet-4-20250514",
                    sessionId: finalSessionId
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

/// Result from a completed agent invocation
struct AgentResult: Sendable {
    let sessionId: String?
    let output: String?
    let costUSD: Double?
    let durationMs: Int?
    let inputTokens: Int
    let outputTokens: Int
}
