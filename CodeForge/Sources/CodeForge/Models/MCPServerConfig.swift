import Foundation
import GRDB

/// Stores MCP server configurations that agents can reference by name.
/// Each record describes how to launch an external MCP server process.
struct MCPServerConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String               // Unique human-readable name, e.g. "filesystem"
    var command: String             // Executable path, e.g. "/usr/local/bin/mcp-filesystem"
    var arguments: String           // JSON-encoded [String], e.g. ["--root", "/tmp"]
    var environmentVars: String     // JSON-encoded [String: String]
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        arguments: [String] = [],
        environmentVars: [String: String] = [:],
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = (try? JSONEncoder().encode(arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.environmentVars = (try? JSONEncoder().encode(environmentVars)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Convenience accessors

    var decodedArguments: [String] {
        guard let data = arguments.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    var decodedEnvironmentVars: [String: String] {
        guard let data = environmentVars.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}

// MARK: - Persistence

extension MCPServerConfig: FetchableRecord, PersistableRecord {
    static let databaseTableName = "mcpServerConfig"
}
