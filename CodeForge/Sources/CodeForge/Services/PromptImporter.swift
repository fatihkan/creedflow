import Foundation
import GRDB

/// Imports prompts from the awesome-chatgpt-prompts CSV repository.
struct PromptImporter: Sendable {
    private let dbQueue: DatabaseQueue

    static let csvURL = URL(string: "https://raw.githubusercontent.com/f/awesome-chatgpt-prompts/main/prompts.csv")!

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Fetches and imports community prompts from CSV. Returns count of newly imported prompts.
    func importFromCSV() async throws -> Int {
        let (data, _) = try await URLSession.shared.data(from: Self.csvURL)
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidData
        }

        let rows = parseCSV(csvString)

        let count = try await dbQueue.write { db -> Int in
            var imported = 0
            for row in rows {
                guard let title = row["act"], let content = row["prompt"],
                      !title.isEmpty, !content.isEmpty else { continue }

                // Skip duplicates (title + source=community)
                let exists = try Prompt
                    .filter(Column("title") == title)
                    .filter(Column("source") == Prompt.Source.community.rawValue)
                    .fetchCount(db) > 0
                guard !exists else { continue }

                let category: String
                if let type = row["type"], !type.isEmpty {
                    category = type
                } else {
                    category = "general"
                }

                var prompt = Prompt(
                    title: title,
                    content: content,
                    source: .community,
                    category: category,
                    contributor: row["contributor"],
                    isBuiltIn: false
                )
                try prompt.insert(db)
                imported += 1
            }
            return imported
        }

        return count
    }

    /// Simple CSV parser that handles quoted fields
    private func parseCSV(_ csv: String) -> [[String: String]] {
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        let headers = parseCSVLine(lines[0])
        var result: [[String: String]] = []

        for i in 1..<lines.count {
            let values = parseCSVLine(lines[i])
            var row: [String: String] = [:]
            for (j, header) in headers.enumerated() {
                let key = header.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                if j < values.count {
                    row[key] = values[j].trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\"", with: "")
                }
            }
            result.append(row)
        }

        return result
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    enum ImportError: LocalizedError {
        case invalidData

        var errorDescription: String? {
            switch self {
            case .invalidData: return "Could not decode CSV data"
            }
        }
    }
}
