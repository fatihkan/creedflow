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

        let startTime = Date()

        // Mark task as in-progress
        try await dbQueue.write { db in
            var updatedTask = task
            updatedTask.status = .inProgress
            updatedTask.startedAt = startTime
            updatedTask.updatedAt = Date()
            try updatedTask.update(db)
        }

        addOutputLine("Starting \(agent.agentType.rawValue) agent for: \(task.title)", type: .system)

        // Build invocation from agent config, override working directory
        var invocation = agent.buildInvocation(for: task)
        if !workingDirectory.isEmpty {
            invocation = ClaudeInvocation(
                prompt: invocation.prompt,
                workingDirectory: workingDirectory,
                systemPrompt: invocation.systemPrompt,
                outputFormat: invocation.outputFormat,
                allowedTools: invocation.allowedTools,
                maxBudgetUSD: invocation.maxBudgetUSD,
                jsonSchema: invocation.jsonSchema,
                resumeSessionId: invocation.resumeSessionId
            )
        }
        let (processId, stream) = await processManager.run(invocation)

        var sessionId: String?
        var resultText: String?
        var totalCost: Double?
        var durationMs: Int?
        var inputTokens = 0
        var outputTokens = 0

        // Set up timeout
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(agent.timeoutSeconds))
            await processManager.cancel(processId)
            throw ClaudeError.timeout
        }

        do {
            // Consume the event stream
            for try await event in stream {
                switch event {
                case .system(let sysEvent):
                    sessionId = sysEvent.sessionId
                    addOutputLine("Session: \(sysEvent.sessionId)", type: .system)

                case .assistant(let assistantEvent):
                    for content in assistantEvent.message.content {
                        if let text = content.text {
                            addOutputLine(text, type: .text)
                        }
                        if let toolName = content.name {
                            addOutputLine("Tool: \(toolName)", type: .toolUse)
                        }
                    }

                case .result(let res):
                    resultText = res.result
                    totalCost = res.totalCostUsd ?? res.cost?.totalUsd
                    durationMs = res.durationMs
                    inputTokens = res.cost?.inputTokens ?? 0
                    outputTokens = res.cost?.outputTokens ?? 0

                    if res.isError == true {
                        addOutputLine("Error: \(res.result ?? "unknown")", type: .error)
                    } else {
                        addOutputLine("Completed successfully", type: .system)
                    }

                case .unknown(let raw):
                    addOutputLine("Unknown event: \(raw.prefix(100))", type: .system)
                }
            }

            timeoutTask.cancel()
        } catch {
            timeoutTask.cancel()
            addOutputLine("Error: \(error.localizedDescription)", type: .error)

            // Update task as failed
            try await dbQueue.write { db in
                var updatedTask = task
                updatedTask.status = .failed
                updatedTask.errorMessage = error.localizedDescription
                updatedTask.updatedAt = Date()
                updatedTask.completedAt = Date()
                try updatedTask.update(db)
            }

            throw error
        }

        let agentResult = AgentResult(
            sessionId: sessionId,
            output: resultText,
            costUSD: totalCost,
            durationMs: durationMs,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )

        // Update task with results
        try await dbQueue.write { db in
            var updatedTask = task
            updatedTask.status = .passed
            updatedTask.result = resultText
            updatedTask.sessionId = sessionId
            updatedTask.costUSD = totalCost
            updatedTask.durationMs = durationMs.map(Int64.init)
            updatedTask.updatedAt = Date()
            updatedTask.completedAt = Date()
            try updatedTask.update(db)
        }

        // Record cost
        if let cost = totalCost, cost > 0 {
            try await dbQueue.write { db in
                var costRecord = CostTracking(
                    projectId: task.projectId,
                    taskId: task.id,
                    agentType: task.agentType,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    costUSD: cost,
                    sessionId: sessionId
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
