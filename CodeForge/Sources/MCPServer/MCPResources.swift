import Foundation
import MCP
import CodeForgeLib

/// Registers CodeForge resources on an MCP Server and handles resource reads via MCPBridge.
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
                uri: "codeforge://projects",
                description: "List of all CodeForge projects",
                mimeType: "application/json"
            ),
            Resource(
                name: "Task Queue",
                uri: "codeforge://tasks/queue",
                description: "Current task queue status (queued + in-progress)",
                mimeType: "application/json"
            ),
            Resource(
                name: "Cost Summary",
                uri: "codeforge://costs/summary",
                description: "Overall cost and token usage summary",
                mimeType: "application/json"
            ),
        ]
    }

    /// Resource templates for parameterized resources
    var resourceTemplates: [Resource.Template] {
        [
            Resource.Template(
                uriTemplate: "codeforge://projects/{id}",
                name: "Project Detail",
                description: "Detailed project info with task counts",
                mimeType: "application/json"
            ),
        ]
    }

    /// Handle a resource read request
    func handleReadResource(uri: String) throws -> ReadResource.Result {
        if uri == "codeforge://projects" {
            return try readProjects()
        } else if uri.hasPrefix("codeforge://projects/") {
            let idStr = String(uri.dropFirst("codeforge://projects/".count))
            guard let id = UUID(uuidString: idStr) else {
                throw MCPError.invalidRequest("Invalid project ID: \(idStr)")
            }
            return try readProjectDetail(id: id)
        } else if uri == "codeforge://tasks/queue" {
            return try readTaskQueue()
        } else if uri == "codeforge://costs/summary" {
            return try readCostSummary()
        } else {
            throw MCPError.invalidRequest("Unknown resource URI: \(uri)")
        }
    }

    // MARK: - Resource Handlers

    private func readProjects() throws -> ReadResource.Result {
        let projects = try bridge.getAllProjects()
        let json = projects.map { p in
            """
            {"id":"\(p.id)","name":"\(p.name)","status":"\(p.status.rawValue)","techStack":"\(p.techStack)"}
            """
        }
        let content = "[\(json.joined(separator: ","))]"
        return ReadResource.Result(contents: [
            .text(content, uri: "codeforge://projects", mimeType: "application/json")
        ])
    }

    private func readProjectDetail(id: UUID) throws -> ReadResource.Result {
        guard let info = try bridge.getProjectStatus(id: id) else {
            throw MCPError.invalidRequest("Project not found: \(id)")
        }
        let content = """
            {"id":"\(info.project.id)","name":"\(info.project.name)","status":"\(info.project.status.rawValue)",\
            "totalTasks":\(info.totalTasks),"completedTasks":\(info.completedTasks),\
            "failedTasks":\(info.failedTasks),"inProgressTasks":\(info.inProgressTasks),\
            "totalCostUSD":\(info.totalCostUSD)}
            """
        return ReadResource.Result(contents: [
            .text(content, uri: "codeforge://projects/\(id)", mimeType: "application/json")
        ])
    }

    private func readTaskQueue() throws -> ReadResource.Result {
        let queue = try bridge.getQueueStatus()
        let format: (AgentTask) -> String = { t in
            """
            {"id":"\(t.id)","title":"\(t.title)","agent":"\(t.agentType.rawValue)","status":"\(t.status.rawValue)","priority":\(t.priority)}
            """
        }
        let queuedJSON = queue.queuedTasks.map(format)
        let activeJSON = queue.inProgressTasks.map(format)
        let content = """
            {"queued":[\(queuedJSON.joined(separator: ","))],"inProgress":[\(activeJSON.joined(separator: ","))]}
            """
        return ReadResource.Result(contents: [
            .text(content, uri: "codeforge://tasks/queue", mimeType: "application/json")
        ])
    }

    private func readCostSummary() throws -> ReadResource.Result {
        let summary = try bridge.getCostSummary()
        let content = """
            {"totalCostUSD":\(summary.totalCostUSD),"totalInputTokens":\(summary.totalInputTokens),\
            "totalOutputTokens":\(summary.totalOutputTokens),"totalInvocations":\(summary.totalInvocations)}
            """
        return ReadResource.Result(contents: [
            .text(content, uri: "codeforge://costs/summary", mimeType: "application/json")
        ])
    }
}
