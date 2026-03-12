import Foundation
import GRDB

/// Executes a PromptChain step-by-step, passing each step's output as `{{previous_output}}`
/// to the next step. Supports conditional branching: if a step has a `condition`, the condition
/// is evaluated after execution. On pass → advance to next step. On fail → jump to
/// `onFailStepOrder` or throw if no target is specified. Cycle detection limits each step
/// to `maxVisitsPerStep` visits.
struct ChainExecutor {
    let dbQueue: DatabaseQueue
    let backendRouter: BackendRouter

    /// Maximum times any single step can be visited before aborting (prevents infinite loops).
    static let maxVisitsPerStep = 3

    enum ChainExecutionError: Error, LocalizedError {
        case chainNotFound(UUID)
        case noSteps(UUID)
        case stepFailed(step: Int, message: String)
        case conditionFailed(step: Int, condition: String)
        case invalidJumpTarget(step: Int, target: Int)
        case cycleLimitReached(step: Int)

        var errorDescription: String? {
            switch self {
            case .chainNotFound(let id):
                return "Prompt chain not found: \(id)"
            case .noSteps(let id):
                return "Prompt chain has no steps: \(id)"
            case .stepFailed(let step, let msg):
                return "Chain step \(step) failed: \(msg)"
            case .conditionFailed(let step, let condition):
                return "Chain step \(step) condition failed: \(condition)"
            case .invalidJumpTarget(let step, let target):
                return "Chain step \(step) has invalid jump target: step order \(target)"
            case .cycleLimitReached(let step):
                return "Chain step \(step) exceeded maximum visit count (\(maxVisitsPerStep))"
            }
        }
    }

    /// Execute all steps in a chain with conditional branching support.
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
        let (_, steps) = try await dbQueue.read { db -> (PromptChain, [PromptChainStep]) in
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

        // Visit counting for cycle detection
        var visitCounts: [Int: Int] = [:]

        // Index-based traversal instead of linear for-loop
        var currentIndex = 0

        while currentIndex < steps.count {
            let step = steps[currentIndex]

            // Cycle guard
            visitCounts[step.stepOrder, default: 0] += 1
            guard visitCounts[step.stepOrder]! <= Self.maxVisitsPerStep else {
                throw ChainExecutionError.cycleLimitReached(step: step.stepOrder)
            }

            guard let prompt = prompts[step.promptId] else {
                currentIndex += 1
                continue
            }

            // Build template values for this step
            var stepValues = templateValues
            stepValues["chain_step"] = String(currentIndex + 1)
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

            // Condition evaluation
            if let conditionJSON = step.condition,
               let condition = ChainCondition.decode(from: conditionJSON) {
                let (reviewScore, reviewVerdict) = await fetchLatestReview(for: task)

                if condition.evaluate(stepOutput: result.output, reviewScore: reviewScore, reviewVerdict: reviewVerdict) {
                    // Condition passed → advance to next step
                    currentIndex += 1
                } else if let targetOrder = step.onFailStepOrder {
                    // Condition failed → jump to target step
                    guard let targetIndex = steps.firstIndex(where: { $0.stepOrder == targetOrder }) else {
                        throw ChainExecutionError.invalidJumpTarget(step: step.stepOrder, target: targetOrder)
                    }
                    currentIndex = targetIndex
                } else {
                    // Condition failed, no fallback target → fail the chain
                    throw ChainExecutionError.conditionFailed(step: step.stepOrder, condition: conditionJSON)
                }
            } else {
                // No condition → linear progression
                currentIndex += 1
            }
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

    /// Fetch the latest review score and verdict for a task.
    private func fetchLatestReview(for task: AgentTask) async -> (Double?, String?) {
        let review = try? await dbQueue.read { db in
            try Review
                .filter(Column("taskId") == task.id)
                .order(Column("createdAt").desc)
                .fetchOne(db)
        }
        return (review?.score, review?.verdict.rawValue)
    }
}
