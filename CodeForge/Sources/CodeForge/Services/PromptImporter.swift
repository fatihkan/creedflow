import Foundation
import GRDB

/// Imports community prompts from the prompts.chat REST API.
struct PromptImporter: Sendable {
    private let dbQueue: DatabaseQueue
    private static let baseURL = "https://prompts.chat/api/prompts"
    private static let perPage = 50

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Fetches all community prompts from prompts.chat, replaces existing community prompts.
    /// Returns count of newly imported prompts.
    func importCommunityPrompts() async throws -> Int {
        // Fetch all pages
        var allPrompts: [APIPrompt] = []
        var page = 1
        var totalPages = 1

        while page <= totalPages {
            let response = try await fetchPage(page)
            allPrompts.append(contentsOf: response.prompts)
            totalPages = response.totalPages
            page += 1
        }

        // Delete old + insert new in a single transaction
        let count = try await dbQueue.write { db -> Int in
            try Prompt
                .filter(Column("source") == Prompt.Source.community.rawValue)
                .deleteAll(db)

            var imported = 0
            for apiPrompt in allPrompts {
                let title = apiPrompt.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let content = apiPrompt.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, !content.isEmpty else { continue }

                let category = apiPrompt.category?.name ?? "general"
                let contributor = apiPrompt.author?.name

                var prompt = Prompt(
                    title: title,
                    content: content,
                    source: .community,
                    category: category,
                    contributor: contributor,
                    isBuiltIn: false
                )
                try prompt.insert(db)
                imported += 1
            }
            return imported
        }

        return count
    }

    // MARK: - API

    private func fetchPage(_ page: Int) async throws -> APIResponse {
        guard var components = URLComponents(string: Self.baseURL) else {
            throw ImportError.invalidData
        }
        components.queryItems = [
            URLQueryItem(name: "perPage", value: "\(Self.perPage)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        guard let url = components.url else {
            throw ImportError.invalidData
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw ImportError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(APIResponse.self, from: data)
    }

    // MARK: - API Response Models

    private struct APIResponse: Decodable {
        let prompts: [APIPrompt]
        let total: Int
        let page: Int
        let perPage: Int
        let totalPages: Int
    }

    private struct APIPrompt: Decodable {
        let title: String
        let content: String
        let type: String?
        let category: APICategory?
        let author: APIAuthor?
    }

    private struct APICategory: Decodable {
        let name: String
        let slug: String
    }

    private struct APIAuthor: Decodable {
        let name: String?
        let username: String?
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case invalidData
        case httpError(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidData:
                return "Could not decode prompt data"
            case .httpError(let code):
                return "Server returned HTTP \(code)"
            }
        }
    }
}
