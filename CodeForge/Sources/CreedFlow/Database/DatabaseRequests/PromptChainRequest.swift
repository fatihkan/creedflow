import Foundation
import GRDB
import Combine

struct PromptChainWithSteps: Equatable, Identifiable {
    var chain: PromptChain
    var steps: [StepWithPrompt]
    var id: UUID { chain.id }

    struct StepWithPrompt: Equatable, Identifiable {
        var step: PromptChainStep
        var prompt: Prompt
        var id: UUID { step.id }
    }
}

@Observable
final class PromptChainStore {
    private(set) var chains: [PromptChain] = []
    private(set) var steps: [UUID: [PromptChainStep]] = [:]
    private var chainCancellable: AnyCancellable?
    private var stepCancellable: AnyCancellable?

    func observe(in dbQueue: DatabaseQueue) {
        chainCancellable = ValueObservation
            .tracking { db in
                try PromptChain
                    .order(Column("name").asc)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] in self?.chains = $0 }
            )

        stepCancellable = ValueObservation
            .tracking { db in
                try PromptChainStep
                    .order(Column("stepOrder").asc)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] allSteps in
                    var byChain: [UUID: [PromptChainStep]] = [:]
                    for step in allSteps {
                        byChain[step.chainId, default: []].append(step)
                    }
                    self?.steps = byChain
                }
            )
    }

    func fetchChainWithSteps(chainId: UUID, in dbQueue: DatabaseQueue) throws -> PromptChainWithSteps? {
        try dbQueue.read { db in
            guard let chain = try PromptChain.fetchOne(db, id: chainId) else { return nil }
            let chainSteps = try PromptChainStep
                .filter(Column("chainId") == chainId)
                .order(Column("stepOrder").asc)
                .fetchAll(db)
            let stepsWithPrompts: [PromptChainWithSteps.StepWithPrompt] = try chainSteps.compactMap { step in
                guard let prompt = try Prompt.fetchOne(db, id: step.promptId) else { return nil }
                return PromptChainWithSteps.StepWithPrompt(step: step, prompt: prompt)
            }
            return PromptChainWithSteps(chain: chain, steps: stepsWithPrompts)
        }
    }

    func composeChainContent(chainId: UUID, in dbQueue: DatabaseQueue) throws -> String {
        guard let chainWithSteps = try fetchChainWithSteps(chainId: chainId, in: dbQueue) else {
            return ""
        }
        var parts: [String] = []
        for (index, stepWithPrompt) in chainWithSteps.steps.enumerated() {
            if index > 0 {
                if let note = stepWithPrompt.step.transitionNote, !note.isEmpty {
                    parts.append("\n---\n\(note)\n")
                } else {
                    parts.append("\n---\n")
                }
            }
            parts.append(stepWithPrompt.prompt.content)
        }
        return parts.joined()
    }
}
