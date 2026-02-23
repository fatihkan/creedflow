import Foundation
import GRDB

struct Prompt: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var content: String
    var source: Source
    var category: String
    var contributor: String?
    var isBuiltIn: Bool
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    enum Source: String, Codable, CaseIterable, DatabaseValueConvertible {
        case user
        case community
    }

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        source: Source = .user,
        category: String = "general",
        contributor: String? = nil,
        isBuiltIn: Bool = false,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.source = source
        self.category = category
        self.contributor = contributor
        self.isBuiltIn = isBuiltIn
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension Prompt: FetchableRecord, PersistableRecord {
    static let databaseTableName = "prompt"
}
