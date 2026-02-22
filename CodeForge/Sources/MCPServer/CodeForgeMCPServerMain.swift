import Foundation
import MCP
import CodeForgeLib

/// Standalone MCP server binary for CodeForge.
/// Runs over stdio, exposing tools and resources that allow external MCP clients
/// (Claude Desktop, agents, etc.) to interact with CodeForge's database.
///
/// Usage:
///   swift run CodeForgeMCPServer
///
/// Claude Desktop config (claude_desktop_config.json):
/// ```json
/// {
///   "mcpServers": {
///     "codeforge": {
///       "command": "/path/to/CodeForgeMCPServer",
///       "args": []
///     }
///   }
/// }
/// ```
@main
struct CodeForgeMCPServerMain {
    static func main() async throws {
        // Initialize database (same path as main app)
        let db = try AppDatabase.makeDefault()
        let bridge = MCPBridge(dbQueue: db.dbQueue)
        let toolRegistrar = MCPToolRegistrar(bridge: bridge)
        let resourceRegistrar = MCPResourceRegistrar(bridge: bridge)

        // Create MCP server
        let server = Server(
            name: "codeforge",
            version: "1.0.0",
            capabilities: .init(
                resources: .init(subscribe: false, listChanged: false),
                tools: .init(listChanged: false)
            )
        )

        // Register handlers (Server is an actor, so use await)
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: toolRegistrar.tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                return try toolRegistrar.handleToolCall(name: params.name, arguments: params.arguments)
            } catch {
                return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
            }
        }

        await server.withMethodHandler(ListResources.self) { _ in
            ListResources.Result(resources: resourceRegistrar.resources)
        }

        await server.withMethodHandler(ListResourceTemplates.self) { _ in
            ListResourceTemplates.Result(templates: resourceRegistrar.resourceTemplates)
        }

        await server.withMethodHandler(ReadResource.self) { params in
            try resourceRegistrar.handleReadResource(uri: params.uri)
        }

        // Start server with stdio transport
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
