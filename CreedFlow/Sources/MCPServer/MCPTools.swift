import Foundation
import MCP
import CreedFlowLib

/// Registers Creed tools on an MCP Server and handles tool calls via MCPBridge.
struct MCPToolRegistrar {
    let bridge: MCPBridge

    init(bridge: MCPBridge) {
        self.bridge = bridge
    }

    /// All tool definitions exposed by Creed
    var tools: [Tool] {
        [
            Tool(
                name: "create_project",
                description: "Create a new Creed project",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": .string("string"), "description": .string("Project name")]),
                        "description": .object(["type": .string("string"), "description": .string("Project description")]),
                        "tech_stack": .object(["type": .string("string"), "description": .string("Technology stack")])
                    ]),
                    "required": .array([.string("name"), .string("description")])
                ])
            ),
            Tool(
                name: "enqueue_task",
                description: "Add a new task to the queue",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_id": .object(["type": .string("string"), "description": .string("Project UUID")]),
                        "agent_type": .object(["type": .string("string"), "enum": .array([.string("analyzer"), .string("coder"), .string("reviewer"), .string("tester"), .string("devops"), .string("monitor"), .string("contentWriter"), .string("designer"), .string("imageGenerator"), .string("videoEditor"), .string("publisher")])]),
                        "title": .object(["type": .string("string"), "description": .string("Task title")]),
                        "description": .object(["type": .string("string"), "description": .string("Task description")]),
                        "priority": .object(["type": .string("integer"), "description": .string("Priority (0=low, higher=more urgent)"), "default": .int(0)])
                    ]),
                    "required": .array([.string("project_id"), .string("agent_type"), .string("title"), .string("description")])
                ])
            ),
            Tool(
                name: "get_project_status",
                description: "Get project status with task summary and cost",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_id": .object(["type": .string("string"), "description": .string("Project UUID")])
                    ]),
                    "required": .array([.string("project_id")])
                ])
            ),
            Tool(
                name: "list_tasks",
                description: "List tasks with optional filters",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_id": .object(["type": .string("string"), "description": .string("Filter by project UUID")]),
                        "status": .object(["type": .string("string"), "enum": .array([.string("queued"), .string("in_progress"), .string("passed"), .string("failed"), .string("needs_revision"), .string("cancelled")])]),
                        "agent_type": .object(["type": .string("string"), "enum": .array([.string("analyzer"), .string("coder"), .string("reviewer"), .string("tester"), .string("devops"), .string("monitor"), .string("contentWriter"), .string("designer"), .string("imageGenerator"), .string("videoEditor"), .string("publisher")])])
                    ])
                ])
            ),
            Tool(
                name: "cancel_task",
                description: "Cancel a queued or in-progress task",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "task_id": .object(["type": .string("string"), "description": .string("Task UUID")])
                    ]),
                    "required": .array([.string("task_id")])
                ])
            ),
            Tool(
                name: "retry_task",
                description: "Re-queue a failed task for retry",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "task_id": .object(["type": .string("string"), "description": .string("Task UUID")])
                    ]),
                    "required": .array([.string("task_id")])
                ])
            ),
            Tool(
                name: "get_agent_logs",
                description: "Get logs for a specific task",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "task_id": .object(["type": .string("string"), "description": .string("Task UUID")]),
                        "limit": .object(["type": .string("integer"), "description": .string("Max log entries"), "default": .int(100)])
                    ]),
                    "required": .array([.string("task_id")])
                ])
            ),
            Tool(
                name: "list_assets",
                description: "List generated assets with optional filters",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_id": .object(["type": .string("string"), "description": .string("Filter by project UUID")]),
                        "asset_type": .object(["type": .string("string"), "enum": .array([.string("image"), .string("video"), .string("audio"), .string("design"), .string("document")]), "description": .string("Filter by asset type")]),
                        "status": .object(["type": .string("string"), "enum": .array([.string("generated"), .string("reviewed"), .string("approved"), .string("rejected")]), "description": .string("Filter by status")])
                    ]),
                    "required": .array([.string("project_id")])
                ])
            ),
            Tool(
                name: "get_asset",
                description: "Get details of a specific generated asset",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "asset_id": .object(["type": .string("string"), "description": .string("Asset UUID")])
                    ]),
                    "required": .array([.string("asset_id")])
                ])
            ),
            Tool(
                name: "list_asset_versions",
                description: "List all versions of an asset",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "asset_id": .object(["type": .string("string"), "description": .string("Asset UUID")])
                    ]),
                    "required": .array([.string("asset_id")])
                ])
            ),
            Tool(
                name: "approve_asset",
                description: "Approve a generated asset",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "asset_id": .object(["type": .string("string"), "description": .string("Asset UUID")])
                    ]),
                    "required": .array([.string("asset_id")])
                ])
            ),
            Tool(
                name: "list_publications",
                description: "List content publications with optional filters",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "project_id": .object(["type": .string("string"), "description": .string("Filter by project UUID")]),
                        "status": .object(["type": .string("string"), "enum": .array([.string("scheduled"), .string("publishing"), .string("published"), .string("failed")])])
                    ])
                ])
            ),
            Tool(
                name: "list_publishing_channels",
                description: "List configured publishing channels",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ),
        ]
    }

    /// Handle a tool call and return the result
    func handleToolCall(name: String, arguments: [String: Value]?) throws -> CallTool.Result {
        let args = arguments ?? [:]

        switch name {
        case "create_project":
            return try handleCreateProject(args)
        case "enqueue_task":
            return try handleEnqueueTask(args)
        case "get_project_status":
            return try handleGetProjectStatus(args)
        case "list_tasks":
            return try handleListTasks(args)
        case "cancel_task":
            return try handleCancelTask(args)
        case "retry_task":
            return try handleRetryTask(args)
        case "get_agent_logs":
            return try handleGetAgentLogs(args)
        case "list_assets":
            return try handleListAssets(args)
        case "get_asset":
            return try handleGetAsset(args)
        case "list_asset_versions":
            return try handleListAssetVersions(args)
        case "approve_asset":
            return try handleApproveAsset(args)
        case "list_publications":
            return try handleListPublications(args)
        case "list_publishing_channels":
            return try handleListPublishingChannels(args)
        default:
            return CallTool.Result(content: [.text("Unknown tool: \(name)")], isError: true)
        }
    }

    // MARK: - Tool Handlers

    private func handleCreateProject(_ args: [String: Value]) throws -> CallTool.Result {
        guard let name = args["name"]?.stringValue,
              let description = args["description"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required: name, description")], isError: true)
        }
        let techStack = args["tech_stack"]?.stringValue ?? ""
        let project = try bridge.createProject(name: name, description: description, techStack: techStack)
        return CallTool.Result(content: [.text("Project created: \(project.name) (id: \(project.id))")])
    }

    private func handleEnqueueTask(_ args: [String: Value]) throws -> CallTool.Result {
        guard let projectIdStr = args["project_id"]?.stringValue,
              let projectId = UUID(uuidString: projectIdStr),
              let agentTypeStr = args["agent_type"]?.stringValue,
              let agentType = AgentTask.AgentType(rawValue: agentTypeStr),
              let title = args["title"]?.stringValue,
              let description = args["description"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required: project_id, agent_type, title, description")], isError: true)
        }
        let priority = args["priority"]?.intValue ?? 0
        let task = try bridge.enqueueTask(
            projectId: projectId,
            agentType: agentType,
            title: title,
            description: description,
            priority: priority
        )
        return CallTool.Result(content: [.text("Task enqueued: \(task.title) (id: \(task.id), agent: \(task.agentType.rawValue))")])
    }

    private func handleGetProjectStatus(_ args: [String: Value]) throws -> CallTool.Result {
        guard let idStr = args["project_id"]?.stringValue,
              let id = UUID(uuidString: idStr) else {
            return CallTool.Result(content: [.text("Missing required: project_id")], isError: true)
        }
        guard let info = try bridge.getProjectStatus(id: id) else {
            return CallTool.Result(content: [.text("Project not found")], isError: true)
        }
        let text = """
            Project: \(info.project.name)
            Status: \(info.project.status.rawValue)
            Tasks: \(info.totalTasks) total, \(info.completedTasks) completed, \(info.failedTasks) failed, \(info.inProgressTasks) in progress
            Cost: $\(String(format: "%.4f", info.totalCostUSD))
            """
        return CallTool.Result(content: [.text(text)])
    }

    private func handleListTasks(_ args: [String: Value]) throws -> CallTool.Result {
        let projectId = args["project_id"]?.stringValue.flatMap(UUID.init(uuidString:))
        let status = args["status"]?.stringValue.flatMap(AgentTask.Status.init(rawValue:))
        let agentType = args["agent_type"]?.stringValue.flatMap(AgentTask.AgentType.init(rawValue:))
        let tasks = try bridge.listTasks(projectId: projectId, status: status, agentType: agentType)
        if tasks.isEmpty {
            return CallTool.Result(content: [.text("No tasks found")])
        }
        let lines = tasks.map { "[\($0.status.rawValue)] \($0.title) (id: \($0.id), agent: \($0.agentType.rawValue))" }
        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    private func handleCancelTask(_ args: [String: Value]) throws -> CallTool.Result {
        guard let idStr = args["task_id"]?.stringValue,
              let id = UUID(uuidString: idStr) else {
            return CallTool.Result(content: [.text("Missing required: task_id")], isError: true)
        }
        let success = try bridge.cancelTask(id: id)
        return CallTool.Result(content: [.text(success ? "Task cancelled" : "Cannot cancel task (not found or not cancellable)")])
    }

    private func handleRetryTask(_ args: [String: Value]) throws -> CallTool.Result {
        guard let idStr = args["task_id"]?.stringValue,
              let id = UUID(uuidString: idStr) else {
            return CallTool.Result(content: [.text("Missing required: task_id")], isError: true)
        }
        let success = try bridge.retryTask(id: id)
        return CallTool.Result(content: [.text(success ? "Task re-queued for retry" : "Cannot retry task (not found or not in failed state)")])
    }

    private func handleGetAgentLogs(_ args: [String: Value]) throws -> CallTool.Result {
        guard let idStr = args["task_id"]?.stringValue,
              let id = UUID(uuidString: idStr) else {
            return CallTool.Result(content: [.text("Missing required: task_id")], isError: true)
        }
        let limit = args["limit"]?.intValue ?? 100
        let logs = try bridge.getAgentLogs(taskId: id, limit: limit)
        if logs.isEmpty {
            return CallTool.Result(content: [.text("No logs found for task")])
        }
        let lines = logs.map { "[\($0.level.rawValue)] \($0.message)" }
        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    private func handleListAssets(_ args: [String: Value]) throws -> CallTool.Result {
        guard let projectIdStr = args["project_id"]?.stringValue,
              let projectId = UUID(uuidString: projectIdStr) else {
            return CallTool.Result(content: [.text("Missing required: project_id")], isError: true)
        }
        let assetType = args["asset_type"]?.stringValue.flatMap(GeneratedAsset.AssetType.init(rawValue:))
        let status = args["status"]?.stringValue.flatMap(GeneratedAsset.Status.init(rawValue:))
        let assets = try bridge.listAssets(projectId: projectId, assetType: assetType, status: status)
        if assets.isEmpty {
            return CallTool.Result(content: [.text("No assets found")])
        }
        let lines = assets.map { "[\($0.status.rawValue)] \($0.name) (id: \($0.id), type: \($0.assetType.rawValue), path: \($0.filePath))" }
        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    private func handleGetAsset(_ args: [String: Value]) throws -> CallTool.Result {
        guard let idStr = args["asset_id"]?.stringValue,
              let id = UUID(uuidString: idStr) else {
            return CallTool.Result(content: [.text("Missing required: asset_id")], isError: true)
        }
        guard let asset = try bridge.getAsset(id: id) else {
            return CallTool.Result(content: [.text("Asset not found")], isError: true)
        }
        let text = """
            Asset: \(asset.name)
            Type: \(asset.assetType.rawValue)
            Status: \(asset.status.rawValue)
            Version: \(asset.version)
            Path: \(asset.filePath)
            Size: \(asset.fileSize ?? 0) bytes
            MIME: \(asset.mimeType ?? "unknown")
            Thumbnail: \(asset.thumbnailPath ?? "none")
            Checksum: \(asset.checksum ?? "none")
            Source URL: \(asset.sourceUrl ?? "none")
            Created: \(asset.createdAt)
            """
        return CallTool.Result(content: [.text(text)])
    }

    private func handleListAssetVersions(_ args: [String: Value]) throws -> CallTool.Result {
        guard let idStr = args["asset_id"]?.stringValue,
              let id = UUID(uuidString: idStr) else {
            return CallTool.Result(content: [.text("Missing required: asset_id")], isError: true)
        }
        let versions = try bridge.listAssetVersions(assetId: id)
        if versions.isEmpty {
            return CallTool.Result(content: [.text("No versions found")])
        }
        let lines = versions.map { "v\($0.version) [\($0.status.rawValue)] \($0.name) (id: \($0.id), checksum: \($0.checksum ?? "none"))" }
        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    private func handleApproveAsset(_ args: [String: Value]) throws -> CallTool.Result {
        guard let idStr = args["asset_id"]?.stringValue,
              let id = UUID(uuidString: idStr) else {
            return CallTool.Result(content: [.text("Missing required: asset_id")], isError: true)
        }
        let success = try bridge.approveAsset(id: id)
        return CallTool.Result(content: [.text(success ? "Asset approved" : "Asset not found")])
    }

    private func handleListPublications(_ args: [String: Value]) throws -> CallTool.Result {
        let projectId = args["project_id"]?.stringValue.flatMap(UUID.init(uuidString:))
        let status = args["status"]?.stringValue.flatMap(Publication.Status.init(rawValue:))
        let pubs = try bridge.listPublications(projectId: projectId, status: status)
        if pubs.isEmpty {
            return CallTool.Result(content: [.text("No publications found")])
        }
        let lines = pubs.map { "[\($0.status.rawValue)] asset:\($0.assetId) → channel:\($0.channelId) (url: \($0.publishedUrl ?? "pending"))" }
        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    private func handleListPublishingChannels(_ args: [String: Value]) throws -> CallTool.Result {
        let channels = try bridge.listPublishingChannels()
        if channels.isEmpty {
            return CallTool.Result(content: [.text("No publishing channels configured")])
        }
        let lines = channels.map { "[\($0.isEnabled ? "enabled" : "disabled")] \($0.name) (\($0.channelType.rawValue), id: \($0.id))" }
        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
