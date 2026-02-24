import Foundation
import GRDB

/// Executes a PromptChain step-by-step, passing each step's output as `{{previous_output}}`
/// to the next step. Accumulates cost across all steps.
struct ChainExecutor {
    let dbQueue: DatabaseQueue
    let backendRouter: BackendRouter

    enum ChainExecutionError: Error, LocalizedError {
        case chainNotFound(UUID)
        case noSteps(UUID)
        case stepFailed(step: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .chainNotFound(let id): return "Prompt chain not found: \(id)"
            case .noSteps(let id): return "Prompt chain has no steps: \(id)"
            case .stepFailed(let step, let msg): return "Chain step \(step) failed: \(msg)"
            }
        }
    }

    /// Execute all steps in a chain sequentially.
    /// Returns the final AgentResult with cumulative cost.
    func execute(
        chainId: UUID,
        task: AgentTask,
        agent: any AgentProtocol,
        workingDirectory: String,
        templateValues: [String: String],
        runner: MultiBackendRunner
    ) async throws -> AgentResult {
        // Fetch chain and steps
        let (chain, steps) = try await dbQueue.read { db -> (PromptChain, [PromptChainStep]) in
            guard let chain = try PromptChain.fetchOne(db, id: chainId) else {
                throw ChainExecutionError.chainNotFound(chainId)
            }
            let steps = try PromptChainStep
                .filter(Column("chainId") == chainId)
                .order(Column("stepOrder").asc)
                .fetchAll(db)
            return (chain, steps)
        }

        guard !steps.isEmpty else {
            throw ChainExecutionError.noSteps(chainId)
        }

        // Fetch all prompts for the chain steps
        let promptIds = steps.map(\.promptId)
        let prompts = try await dbQueue.read { db -> [UUID: Prompt] in
            let fetched = try Prompt.filter(ids: promptIds).fetchAll(db)
            return Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        }

        var previousOutput: String?
        var cumulativeCost: Double = 0
        var cumulativeInputTokens = 0
        var cumulativeOutputTokens = 0
        var lastSessionId: String?
        var lastDurationMs: Int?
        let totalSteps = steps.count

        for (index, step) in steps.enumerated() {
            guard let prompt = prompts[step.promptId] else { continue }

            // Build template values for this step
            var stepValues = templateValues
            stepValues["chain_step"] = String(index + 1)
            stepValues["chain_total_steps"] = String(totalSteps)
            if let prev = previousOutput {
                stepValues["previous_output"] = prev
            }

            // Resolve template variables in prompt content
            let resolvedPrompt = TemplateVariableResolver.resolve(template: prompt.content, values: stepValues)

            // Prepend transition note if present
            let finalPrompt: String
            if let note = step.transitionNote, !note.isEmpty {
                finalPrompt = "[\(note)]\n\n\(resolvedPrompt)"
            } else {
                finalPrompt = resolvedPrompt
            }

            // Execute this step
            let result = try await runner.execute(
                task: task,
                agent: agent,
                workingDirectory: workingDirectory,
                promptOverride: finalPrompt
            )

            // Accumulate results
            previousOutput = result.output
            if let cost = result.costUSD { cumulativeCost += cost }
            cumulativeInputTokens += result.inputTokens
            cumulativeOutputTokens += result.outputTokens
            lastSessionId = result.sessionId ?? lastSessionId
            lastDurationMs = result.durationMs ?? lastDurationMs

            // Record usage for each step
            let recommender = PromptRecommender(dbQueue: dbQueue)
            recommender.recordUsage(
                promptId: prompt.id,
                projectId: task.projectId,
                taskId: task.id,
                agentType: task.agentType,
                chainId: chainId
            )
        }

        return AgentResult(
            sessionId: lastSessionId,
            output: previousOutput,
            costUSD: cumulativeCost > 0 ? cumulativeCost : nil,
            durationMs: lastDurationMs,
            inputTokens: cumulativeInputTokens,
            outputTokens: cumulativeOutputTokens
        )
    }
}
