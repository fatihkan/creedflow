import Foundation
import GRDB
import Combine

/// Observable store for prompt records
@Observable
final class PromptStore {
    private(set) var prompts: [Prompt] = []
    private var cancellable: AnyCancellable?

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
    }

    func filtered(searchText: String, source: Prompt.Source?, category: String?) -> [Prompt] {
        prompts.filter { prompt in
            let matchesSearch = searchText.isEmpty
                || prompt.title.localizedCaseInsensitiveContains(searchText)
                || prompt.content.localizedCaseInsensitiveContains(searchText)
            let matchesSource = source == nil || prompt.source == source
            let matchesCategory = category == nil || category == "all" || prompt.category == category
            return matchesSearch && matchesSource && matchesCategory
        }
    }

    var categories: [String] {
        Array(Set(prompts.map(\.category))).sorted()
    }
}
