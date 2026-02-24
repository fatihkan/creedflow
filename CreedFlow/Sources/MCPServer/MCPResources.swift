import Foundation
import MCP
import CreedFlowLib

/// Registers Creed resources on an MCP Server and handles resource reads via MCPBridge.
struct MCPResourceRegistrar {
    let bridge: MCPBridge

    init(bridge: MCPBridge) {
        self.bridge = bridge
    }

    /// Static resource definitions
    var resources: [Resource] {
        [
            Resource(
                name: "All Projects",
                uri: "creedflow://projects",
                description: "List of all Creed projects",
                mimeType: "application/json"
            ),
            Resource(
                name: "Task Queue",
                uri: "creedflow://tasks/queue",
                description: "Current task queue status (queued + in-progress)",
                mimeType: "application/json"
            ),
            Resource(
                name: "Cost Summary",
                uri: "creedflow://costs/summary",
                description: "Overall cost and token usage summary",
                mimeType: "application/json"
            ),
        ]
    }

    /// Resource templates for parameterized resources
    var resourceTemplates: [Resource.Template] {
        [
            Resource.Template(
                uriTemplate: "creedflow://projects/{id}",
                name: "Project Detail",
                description: "Detailed project info with task counts",
                mimeType: "application/json"
            ),
            Resource.Template(
                uriTemplate: "creedflow://projects/{id}/assets",
                name: "Project Assets",
                description: "Generated assets for a project with summary",
                mimeType: "application/json"
            ),
        ]
    }

    /// Handle a resource read request
    func handleReadResource(uri: String) throws -> ReadResource.Result {
        if uri == "creedflow://projects" {
            return try readProjects()
        } else if uri.hasPrefix("creedflow://projects/") {
            let remainder = String(uri.dropFirst("creedflow://projects/".count))
            // Check for /assets suffix before plain project ID
            if remainder.hasSuffix("/assets") {
                let idStr = String(remainder.dropLast("/assets".count))
                guard let id = UUID(uuidString: idStr) else {
                    throw MCPError.invalidRequest("Invalid project ID: \(idStr)")
                }
                return try readProjectAssets(id: id)
            }
            guard let id = UUID(uuidString: remainder) else {
                throw MCPError.invalidRequest("Invalid project ID: \(remainder)")
            }
            return try readProjectDetail(id: id)
        } else if uri == "creedflow://tasks/queue" {
            return try readTaskQueue()
        } else if uri == "creedflow://costs/summary" {
            return try readCostSummary()
        } else {
            throw MCPError.invalidRequest("Unknown resource URI: \(uri)")
        }
    }

    // MARK: - Resource Handlers

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    private func readProjects() throws -> ReadResource.Result {
        let projects = try bridge.getAllProjects()
        let items: [[String: Any]] = projects.map { p in
            ["id": p.id.uuidString, "name": p.name, "status": p.status.rawValue, "techStack": p.techStack]
        }
        let data = try JSONSerialization.data(withJSONObject: items)
        let content = String(data: data, encoding: .utf8) ?? "[]"
        return ReadResource.Result(contents: [
            .text(content, uri: "creedflow://projects", mimeType: "application/json")
        ])
    }

    private func readProjectDetail(id: UUID) throws -> ReadResource.Result {
        guard let info = try bridge.getProjectStatus(id: id) else {
            throw MCPError.invalidRequest("Project not found: \(id)")
        }
        let dict: [String: Any] = [
            "id": info.project.id.uuidString, "name": info.project.name,
            "status": info.project.status.rawValue,
            "totalTasks": info.totalTasks, "completedTasks": info.completedTasks,
            "failedTasks": info.failedTasks, "inProgressTasks": info.inProgressTasks,
            "totalCostUSD": info.totalCostUSD
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let content = String(data: data, encoding: .utf8) ?? "{}"
        return ReadResource.Result(contents: [
            .text(content, uri: "creedflow://projects/\(id)", mimeType: "application/json")
        ])
    }

    private func readProjectAssets(id: UUID) throws -> ReadResource.Result {
        let summary = try bridge.getProjectAssetSummary(projectId: id)
        let assets = try bridge.listAssets(projectId: id)
        let assetItems: [[String: Any]] = assets.map { a in
            ["id": a.id.uuidString, "name": a.name, "type": a.assetType.rawValue,
             "status": a.status.rawValue, "filePath": a.filePath,
             "fileSize": a.fileSize ?? 0]
        }
        let dict: [String: Any] = [
            "totalAssets": summary.totalAssets,
            "approvedAssets": summary.approvedAssets,
            "assetsByType": summary.assetsByType,
            "assets": assetItems
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let content = String(data: data, encoding: .utf8) ?? "{}"
        return ReadResource.Result(contents: [
            .text(content, uri: "creedflow://projects/\(id)/assets", mimeType: "application/json")
        ])
    }

    private func readTaskQueue() throws -> ReadResource.Result {
        let queue = try bridge.getQueueStatus()
        let format: (AgentTask) -> [String: Any] = { t in
            ["id": t.id.uuidString, "title": t.title, "agent": t.agentType.rawValue,
             "status": t.status.rawValue, "priority": t.priority]
        }
        let dict: [String: Any] = [
            "queued": queue.queuedTasks.map(format),
            "inProgress": queue.inProgressTasks.map(format)
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let content = String(data: data, encoding: .utf8) ?? "{}"
        return ReadResource.Result(contents: [
            .text(content, uri: "creedflow://tasks/queue", mimeType: "application/json")
        ])
    }

    private func readCostSummary() throws -> ReadResource.Result {
        let summary = try bridge.getCostSummary()
        let dict: [String: Any] = [
            "totalCostUSD": summary.totalCostUSD, "totalInputTokens": summary.totalInputTokens,
            "totalOutputTokens": summary.totalOutputTokens, "totalInvocations": summary.totalInvocations
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let content = String(data: data, encoding: .utf8) ?? "{}"
        return ReadResource.Result(contents: [
            .text(content, uri: "creedflow://costs/summary", mimeType: "application/json")
        ])
    }
}
