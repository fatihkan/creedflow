import Foundation
import GRDB

/// Recommends the best prompt for a given agent type based on effectiveness metrics,
/// and records usage automatically on dispatch.
struct PromptRecommender {
    let dbQueue: DatabaseQueue

    struct Recommendation {
        let prompt: Prompt
        let score: Double
    }

    /// Find the highest-scoring prompt for the given agent type category.
    /// Score = (successRate * 0.5) + (avgReviewScore/10 * 0.3) + (min(usageCount/10, 1) * 0.2)
    func recommend(for agentType: AgentTask.AgentType) -> Recommendation? {
        let category = Self.category(for: agentType)
        guard let result = try? dbQueue.read({ db -> Recommendation? in
            let prompts = try Prompt
                .filter(Column("category") == category)
                .fetchAll(db)

            guard !prompts.isEmpty else { return nil }

            var best: Recommendation?
            for prompt in prompts {
                let usages = try PromptUsage
                    .filter(Column("promptId") == prompt.id)
                    .fetchAll(db)

                let score = Self.computeScore(usages: usages)
                if best == nil || score > best!.score {
                    best = Recommendation(prompt: prompt, score: score)
                }
            }
            return best
        }) else {
            return nil
        }
        return result
    }

    /// Record a prompt usage entry when a task is dispatched.
    func recordUsage(
        promptId: UUID,
        projectId: UUID,
        taskId: UUID,
        agentType: AgentTask.AgentType,
        chainId: UUID? = nil
    ) {
        let usage = PromptUsage(
            promptId: promptId,
            projectId: projectId,
            taskId: taskId,
            chainId: chainId,
            agentType: agentType.rawValue
        )
        _ = try? dbQueue.write { db in
            try usage.insert(db)
        }
    }

    // MARK: - Private

    static func computeScore(usages: [PromptUsage]) -> Double {
        let usageCount = usages.count
        guard usageCount > 0 else { return 0.2 } // Base score for unused prompts

        let withOutcome = usages.filter { $0.outcome != nil }
        let successRate: Double
        if !withOutcome.isEmpty {
            let successes = withOutcome.filter { $0.outcome == .completed }.count
            successRate = Double(successes) / Double(withOutcome.count)
        } else {
            successRate = 0.5 // Neutral when no outcomes yet
        }

        let scores = usages.compactMap(\.reviewScore)
        let avgReviewScore: Double
        if !scores.isEmpty {
            avgReviewScore = scores.reduce(0, +) / Double(scores.count)
        } else {
            avgReviewScore = 5.0 // Neutral default
        }

        let usageFactor = min(Double(usageCount) / 10.0, 1.0)

        return (successRate * 0.5) + (avgReviewScore / 10.0 * 0.3) + (usageFactor * 0.2)
    }

    /// Map agent types to prompt categories.
    static func category(for agentType: AgentTask.AgentType) -> String {
        switch agentType {
        case .analyzer: return "analyzer"
        case .coder: return "coder"
        case .reviewer: return "reviewer"
        case .tester: return "tester"
        case .devops: return "devops"
        case .monitor: return "monitor"
        case .contentWriter: return "content"
        case .designer: return "design"
        case .imageGenerator: return "image"
        case .videoEditor: return "video"
        }
    }
}
