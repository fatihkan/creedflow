import Foundation
import GRDB
import os.log

/// Evaluates automation flow triggers and executes their corresponding actions.
/// Called by Orchestrator after task/deploy/review events to process matching flows.
package actor AutomationEngine {
    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: "com.creedflow", category: "AutomationEngine")

    package init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Called by Orchestrator when an event occurs that may match automation triggers.
    ///
    /// - Parameters:
    ///   - type: The trigger type string (e.g. "task_completed", "deploy_success")
    ///   - context: Key-value context about the event (e.g. agentType, projectId, environment)
    package func evaluateTrigger(type: String, context: [String: String]) async {
        do {
            // 1. Query enabled flows matching triggerType
            let flows = try await dbQueue.read { db in
                try AutomationFlow
                    .filter(Column("isEnabled") == true)
                    .filter(Column("triggerType") == type)
                    .fetchAll(db)
            }

            guard !flows.isEmpty else { return }

            for flow in flows {
                // 2. If flow is project-scoped, check context projectId matches
                if let flowProjectId = flow.projectId {
                    guard context["projectId"] == flowProjectId else { continue }
                }

                // 3. Check if triggerConfig matches context
                guard matchesTriggerConfig(flow: flow, context: context) else { continue }

                // 4. Execute the action
                do {
                    try await executeAction(flow: flow, context: context)
                    logger.info("Automation flow '\(flow.name)' triggered successfully")
                } catch {
                    logger.error("Automation flow '\(flow.name)' action failed: \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("Failed to evaluate automation triggers: \(error.localizedDescription)")
        }
    }

    // MARK: - Trigger Matching

    /// Check if the flow's triggerConfig JSON matches the event context.
    /// An empty config or `{}` matches everything. Otherwise each key in the config
    /// must match the corresponding key in context.
    private func matchesTriggerConfig(flow: AutomationFlow, context: [String: String]) -> Bool {
        let configStr = flow.triggerConfig.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configStr.isEmpty, configStr != "{}" else { return true }

        guard let data = configStr.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return true // Can't parse — treat as match
        }

        for (key, value) in config {
            guard let contextValue = context[key] else { return false }
            if let stringValue = value as? String {
                if contextValue != stringValue { return false }
            } else if let numValue = value as? Double {
                if Double(contextValue) != numValue { return false }
            }
        }

        return true
    }

    // MARK: - Action Execution

    private func executeAction(flow: AutomationFlow, context: [String: String]) async throws {
        switch flow.actionType {
        case "create_task":
            try await executeCreateTask(flow: flow, context: context)
        case "send_notification":
            try await executeSendNotification(flow: flow, context: context)
        case "deploy":
            try await executeDeploy(flow: flow, context: context)
        case "run_command":
            try await executeRunCommand(flow: flow, context: context)
        default:
            logger.warning("Unknown action type: \(flow.actionType)")
        }

        // Update lastTriggeredAt
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE automationFlow SET lastTriggeredAt = ?, updatedAt = ? WHERE id = ?",
                arguments: [Date(), Date(), flow.id]
            )
        }
    }

    private func executeCreateTask(flow: AutomationFlow, context: [String: String]) async throws {
        guard let data = flow.actionConfig.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AutomationError.invalidConfig("Cannot parse action config JSON")
        }

        let agentTypeStr = config["agentType"] as? String ?? "coder"
        let title = config["title"] as? String ?? "Auto-created task from '\(flow.name)'"
        let description = config["description"] as? String ?? "Automatically created by automation flow '\(flow.name)'"
        let priority = config["priority"] as? Int ?? 5

        guard let agentType = AgentTask.AgentType(rawValue: agentTypeStr) else {
            throw AutomationError.invalidConfig("Unknown agent type: \(agentTypeStr)")
        }

        // Use projectId from flow or context
        let projectIdStr = flow.projectId ?? context["projectId"]
        guard let projectIdStr, let projectId = UUID(uuidString: projectIdStr) else {
            throw AutomationError.invalidConfig("No projectId available for create_task action")
        }

        let task = AgentTask(
            projectId: projectId,
            agentType: agentType,
            title: title,
            description: description,
            priority: priority
        )

        try await dbQueue.write { db in
            var t = task
            try t.insert(db)
        }

        logger.info("Created task '\(title)' for agent \(agentTypeStr) via automation")
    }

    private func executeSendNotification(flow: AutomationFlow, context: [String: String]) async throws {
        guard let data = flow.actionConfig.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AutomationError.invalidConfig("Cannot parse action config JSON")
        }

        let message = config["message"] as? String ?? "Automation '\(flow.name)' triggered"

        // Create an in-app notification
        try await dbQueue.write { db in
            let notification = AppNotification(
                category: .task,
                severity: .info,
                title: "Automation: \(flow.name)",
                message: message
            )
            try notification.insert(db)
        }
    }

    private func executeDeploy(flow: AutomationFlow, context: [String: String]) async throws {
        guard let data = flow.actionConfig.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AutomationError.invalidConfig("Cannot parse action config JSON")
        }

        let environmentStr = config["environment"] as? String ?? "staging"
        let environment = Deployment.Environment(rawValue: environmentStr) ?? .staging

        let projectIdStr = flow.projectId ?? context["projectId"]
        guard let projectIdStr, let projectId = UUID(uuidString: projectIdStr) else {
            throw AutomationError.invalidConfig("No projectId available for deploy action")
        }

        let deployment = Deployment(
            projectId: projectId,
            environment: environment,
            version: "auto-\(flow.name)",
            deployedBy: "automation"
        )

        let devopsTask = AgentTask(
            projectId: projectId,
            agentType: .devops,
            title: "Deploy (\(environmentStr)) via automation '\(flow.name)'",
            description: "Automated deployment triggered by flow '\(flow.name)'",
            priority: 10
        )

        try await dbQueue.write { db in
            var d = deployment
            try d.insert(db)
            var t = devopsTask
            try t.insert(db)
        }

        logger.info("Created deployment and DevOps task via automation '\(flow.name)'")
    }

    private func executeRunCommand(flow: AutomationFlow, context: [String: String]) async throws {
        guard let data = flow.actionConfig.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AutomationError.invalidConfig("Cannot parse action config JSON")
        }

        let command = config["command"] as? String ?? ""
        guard !command.isEmpty else {
            throw AutomationError.invalidConfig("No command specified in action config")
        }

        // Run the command as a subprocess
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        // Set working directory from context if available
        if let projectId = flow.projectId ?? context["projectId"] {
            let project = try? await dbQueue.read { db in
                try Project.fetchOne(db, id: UUID(uuidString: projectId) ?? UUID())
            }
            if let dir = project?.directoryPath, !dir.isEmpty {
                process.currentDirectoryURL = URL(fileURLWithPath: dir)
            }
        }

        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            logger.warning("Command '\(command)' exited with status \(process.terminationStatus): \(output)")
        } else {
            logger.info("Command '\(command)' completed successfully")
        }
    }
}

// MARK: - Error

enum AutomationError: Error, LocalizedError {
    case invalidConfig(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfig(let msg): return "Automation config error: \(msg)"
        }
    }
}
