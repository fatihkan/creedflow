import Foundation
import GRDB

package struct AutomationFlow: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    package var id: String
    package var projectId: String?
    package var name: String
    package var triggerType: String
    package var triggerConfig: String
    package var actionType: String
    package var actionConfig: String
    package var isEnabled: Bool
    package var lastTriggeredAt: Date?
    package var createdAt: Date
    package var updatedAt: Date

    package static var databaseTableName = "automationFlow"

    package init(
        id: String = UUID().uuidString,
        projectId: String? = nil,
        name: String,
        triggerType: String,
        triggerConfig: String = "{}",
        actionType: String,
        actionConfig: String = "{}",
        isEnabled: Bool = true,
        lastTriggeredAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.triggerType = triggerType
        self.triggerConfig = triggerConfig
        self.actionType = actionType
        self.actionConfig = actionConfig
        self.isEnabled = isEnabled
        self.lastTriggeredAt = lastTriggeredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Trigger & Action Types

extension AutomationFlow {
    package enum TriggerType: String, CaseIterable, Codable, Sendable {
        case taskCompleted = "task_completed"
        case taskFailed = "task_failed"
        case deploySuccess = "deploy_success"
        case deployFailed = "deploy_failed"
        case reviewPassed = "review_passed"
        case reviewFailed = "review_failed"
        case schedule = "schedule"

        package var displayName: String {
            switch self {
            case .taskCompleted: return "Task Completed"
            case .taskFailed: return "Task Failed"
            case .deploySuccess: return "Deploy Success"
            case .deployFailed: return "Deploy Failed"
            case .reviewPassed: return "Review Passed"
            case .reviewFailed: return "Review Failed"
            case .schedule: return "Schedule"
            }
        }
    }

    package enum ActionType: String, CaseIterable, Codable, Sendable {
        case createTask = "create_task"
        case sendNotification = "send_notification"
        case runCommand = "run_command"
        case deploy = "deploy"

        package var displayName: String {
            switch self {
            case .createTask: return "Create Task"
            case .sendNotification: return "Send Notification"
            case .runCommand: return "Run Command"
            case .deploy: return "Deploy"
            }
        }
    }
}
