import Foundation
import GRDB

/// Generates temporary MCP config JSON files for the Claude CLI `--mcp-config` flag.
/// Each file is created on demand and cleaned up after the agent process finishes.
struct MCPConfigGenerator: Sendable {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Claude CLI expects this JSON format:
    /// ```json
    /// {
    ///   "mcpServers": {
    ///     "name": { "command": "...", "args": [...], "env": {...} }
    ///   }
    /// }
    /// ```
    struct MCPConfigFile: Encodable {
        let mcpServers: [String: ServerEntry]

        struct ServerEntry: Encodable {
            let command: String
            let args: [String]
            let env: [String: String]
        }
    }

    /// Generate a temporary JSON config file for the given MCP server names.
    /// Returns the file path, or nil if no servers matched.
    func generateConfig(serverNames: [String]) throws -> String? {
        guard !serverNames.isEmpty else { return nil }

        let configs = try dbQueue.read { db in
            try MCPServerConfig.fetchEnabled(names: serverNames, in: db)
        }

        guard !configs.isEmpty else { return nil }

        var servers: [String: MCPConfigFile.ServerEntry] = [:]
        for config in configs {
            servers[config.name] = MCPConfigFile.ServerEntry(
                command: config.command,
                args: config.decodedArguments,
                env: config.decodedEnvironmentVars
            )
        }

        let configFile = MCPConfigFile(mcpServers: servers)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configFile)

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "creed-mcp-\(UUID().uuidString.prefix(8)).json"
        let filePath = tempDir.appendingPathComponent(fileName)
        try data.write(to: filePath)

        return filePath.path
    }

    /// Remove a previously generated config file.
    static func cleanup(path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
