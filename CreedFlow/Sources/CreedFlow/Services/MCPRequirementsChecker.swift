import Foundation
import GRDB

struct MCPCheckResult: Identifiable {
    let id: String          // MCP server name
    let displayName: String
    let isConfigured: Bool
}

struct MCPRequirementsChecker {

    /// MCP server names required (or recommended) for a given project type.
    static func requiredServers(for type: Project.ProjectType) -> [String] {
        switch type {
        case .software, .content, .general, .automation:
            return ["creedflow"]
        case .image:
            return ["dalle", "stability", "replicate", "leonardo"]
        case .video:
            return ["runway", "elevenlabs", "heygen", "replicate"]
        }
    }

    /// Human-readable display names for MCP servers.
    private static let displayNames: [String: String] = [
        "creedflow": "CreedFlow",
        "dalle": "DALL-E",
        "stability": "Stability AI",
        "replicate": "Replicate",
        "leonardo": "Leonardo.AI",
        "runway": "Runway",
        "elevenlabs": "ElevenLabs",
        "heygen": "HeyGen",
    ]

    /// Whether at least one creative MCP must be configured (image/video) vs all must be present.
    static func requiresAtLeastOne(for type: Project.ProjectType) -> Bool {
        switch type {
        case .image, .video: return true
        default: return false
        }
    }

    /// Check which required MCP servers are configured for a project type.
    static func check(for type: Project.ProjectType, in dbQueue: DatabaseQueue) async -> [MCPCheckResult] {
        let names = requiredServers(for: type)
        guard !names.isEmpty else { return [] }

        let configured: Set<String>
        do {
            configured = try await dbQueue.read { db in
                let configs = try MCPServerConfig.fetchEnabled(names: names, in: db)
                return Set(configs.map(\.name))
            }
        } catch {
            configured = []
        }

        return names.map { name in
            MCPCheckResult(
                id: name,
                displayName: displayNames[name] ?? name.capitalized,
                isConfigured: configured.contains(name)
            )
        }
    }
}
