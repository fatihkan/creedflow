import Foundation

/// CLIBackend adapter that wraps the existing ClaudeProcessManager.
/// Translates CLITaskInput → ClaudeInvocation and ClaudeStreamEvent → CLIOutputEvent.
actor ClaudeBackend: CLIBackend {
    nonisolated let backendType = CLIBackendType.claude
    private let processManager: ClaudeProcessManager

    init(processManager: ClaudeProcessManager) {
        self.processManager = processManager
    }

    var isAvailable: Bool {
        // Claude is always considered available if the app is running
        // (path resolution handled at init time by Orchestrator)
        true
    }

    func execute(_ input: CLITaskInput) async -> (id: UUID, stream: AsyncThrowingStream<CLIOutputEvent, Error>) {
        let invocation = ClaudeInvocation(
            prompt: input.prompt,
            workingDirectory: input.workingDirectory,
            systemPrompt: input.systemPrompt,
            outputFormat: .streamJSON,
            allowedTools: input.allowedTools,
            maxBudgetUSD: input.maxBudgetUSD,
            jsonSchema: input.jsonSchema,
            mcpConfigPath: input.mcpConfigPath
        )

        let (processId, claudeStream) = await processManager.run(invocation)

        let outputStream = AsyncThrowingStream<CLIOutputEvent, Error> { continuation in
            let task = Task {
                do {
                    for try await event in claudeStream {
                        let mapped = Self.mapEvent(event)
                        for output in mapped {
                            continuation.yield(output)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        return (processId, outputStream)
    }

    func cancel(_ processId: UUID) async {
        await processManager.cancel(processId)
    }

    func cancelAll() async {
        await processManager.cancelAll()
    }

    func activeCount() -> Int {
        // ClaudeProcessManager is an actor — need to call synchronously here
        // since we're already in an actor context. Use a workaround.
        0 // Will be called via await from outside
    }

    nonisolated func activeCountAsync() async -> Int {
        await processManager.activeCount()
    }

    // MARK: - Event Mapping

    private static func mapEvent(_ event: ClaudeStreamEvent) -> [CLIOutputEvent] {
        switch event {
        case .system(let sys):
            return [.system(sessionId: sys.sessionId, model: sys.model)]

        case .assistant(let assistant):
            var outputs: [CLIOutputEvent] = []
            for content in assistant.message.content {
                if let text = content.text {
                    outputs.append(.text(text))
                }
                if let name = content.name {
                    outputs.append(.toolUse(name: name))
                }
            }
            return outputs

        case .result(let res):
            let result = CLIResult(
                output: res.result,
                isError: res.isError ?? false,
                sessionId: res.sessionId,
                model: nil,
                costUSD: res.totalCostUsd ?? res.cost?.totalUsd,
                durationMs: res.durationMs,
                inputTokens: res.cost?.inputTokens ?? 0,
                outputTokens: res.cost?.outputTokens ?? 0
            )
            return [.result(result)]

        case .ignored, .unknown:
            return []
        }
    }
}
