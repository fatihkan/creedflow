import Foundation
import GRDB

struct PromptExporter {

    // MARK: - Export Types

    struct ExportedPrompt: Codable {
        var title: String
        var content: String
        var category: String
        var tags: [String]
        var version: Int
        var contributor: String?
    }

    struct ExportBundle: Codable {
        var schemaVersion: Int = 1
        var exportedAt: Date
        var prompts: [ExportedPrompt]
    }

    // MARK: - Export

    static func export(prompts: [Prompt], tags: [UUID: [String]]) throws -> Data {
        let exported = prompts.map { prompt in
            ExportedPrompt(
                title: prompt.title,
                content: prompt.content,
                category: prompt.category,
                tags: tags[prompt.id] ?? [],
                version: prompt.version,
                contributor: prompt.contributor
            )
        }
        let bundle = ExportBundle(exportedAt: Date(), prompts: exported)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    // MARK: - Import

    static func importPrompts(from data: Data, into dbQueue: DatabaseQueue) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        var count = 0
        try dbQueue.write { db in
            for exported in bundle.prompts {
                // Skip duplicates by title
                let exists = try Prompt
                    .filter(Column("title") == exported.title)
                    .fetchCount(db) > 0
                if exists { continue }

                var prompt = Prompt(
                    title: exported.title,
                    content: exported.content,
                    source: .user,
                    category: exported.category,
                    contributor: exported.contributor,
                    version: exported.version
                )
                try prompt.insert(db)

                for tag in exported.tags {
                    try PromptTag(promptId: prompt.id, tag: tag).insert(db)
                }
                count += 1
            }
        }
        return count
    }
}
