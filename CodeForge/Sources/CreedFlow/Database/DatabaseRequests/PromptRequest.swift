import Foundation
import GRDB
import Combine

struct PromptStats: Equatable {
    var usageCount: Int
    var successRate: Double?
    var averageReviewScore: Double?
}

/// Observable store for prompt records
@Observable
final class PromptStore {
    private(set) var prompts: [Prompt] = []
    private(set) var allTags: [String] = []
    private(set) var promptTags: [UUID: [String]] = [:]
    private var cancellable: AnyCancellable?
    private var tagCancellable: AnyCancellable?

    func observe(in dbQueue: DatabaseQueue) {
        cancellable = ValueObservation
            .tracking { db in
                try Prompt
                    .order(Column("isFavorite").desc, Column("title").asc)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] in self?.prompts = $0 }
            )

        tagCancellable = ValueObservation
            .tracking { db in
                try PromptTag.fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] tags in
                    var byPrompt: [UUID: [String]] = [:]
                    var allSet = Set<String>()
                    for tag in tags {
                        byPrompt[tag.promptId, default: []].append(tag.tag)
                        allSet.insert(tag.tag)
                    }
                    self?.promptTags = byPrompt
                    self?.allTags = allSet.sorted()
                }
            )
    }

    func filtered(searchText: String, source: Prompt.Source?, category: String?, tag: String? = nil) -> [Prompt] {
        prompts.filter { prompt in
            let matchesSearch = searchText.isEmpty
                || prompt.title.localizedCaseInsensitiveContains(searchText)
                || prompt.content.localizedCaseInsensitiveContains(searchText)
            let matchesSource = source == nil || prompt.source == source
            let matchesCategory = category == nil || category == "all" || prompt.category == category
            let matchesTag: Bool
            if let tag, !tag.isEmpty {
                matchesTag = promptTags[prompt.id]?.contains(tag) == true
            } else {
                matchesTag = true
            }
            return matchesSearch && matchesSource && matchesCategory && matchesTag
        }
    }

    var categories: [String] {
        Array(Set(prompts.map(\.category))).sorted()
    }

    func fetchVersionHistory(for promptId: UUID, in dbQueue: DatabaseQueue) throws -> [PromptVersion] {
        try dbQueue.read { db in
            try PromptVersion
                .filter(Column("promptId") == promptId)
                .order(Column("version").desc)
                .fetchAll(db)
        }
    }

    func fetchUsageStats(for promptId: UUID, in dbQueue: DatabaseQueue) throws -> PromptStats {
        try dbQueue.read { db in
            let usages = try PromptUsage
                .filter(Column("promptId") == promptId)
                .fetchAll(db)
            let count = usages.count
            guard count > 0 else {
                return PromptStats(usageCount: 0)
            }
            let withOutcome = usages.filter { $0.outcome != nil }
            let successRate: Double?
            if !withOutcome.isEmpty {
                let successes = withOutcome.filter { $0.outcome == .completed }.count
                successRate = Double(successes) / Double(withOutcome.count)
            } else {
                successRate = nil
            }
            let withScore = usages.compactMap(\.reviewScore)
            let avgScore: Double?
            if !withScore.isEmpty {
                avgScore = withScore.reduce(0, +) / Double(withScore.count)
            } else {
                avgScore = nil
            }
            return PromptStats(usageCount: count, successRate: successRate, averageReviewScore: avgScore)
        }
    }
}
