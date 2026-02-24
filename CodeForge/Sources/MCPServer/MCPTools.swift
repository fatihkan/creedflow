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
                        "agent_type": .object(["type": .string("string"), "enum": .array([.string("analyzer"), .string("coder"), .string("reviewer"), .string("tester"), .string("devops"), .string("monitor")])]),
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
                        "agent_type": .object(["type": .string("string"), "enum": .array([.string("analyzer"), .string("coder"), .string("reviewer"), .string("tester"), .string("devops"), .string("monitor")])])
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
}
