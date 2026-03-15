import Foundation
import GRDB
import os.log

/// Stub for Jira issue sync — not yet implemented.
package actor JiraSyncService {
    private let logger = Logger(subsystem: "com.creedflow", category: "JiraSync")
    private let dbQueue: DatabaseQueue

    package init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    package func importIssues(config: IssueTrackingConfig) async throws -> [IssueMapping] {
        throw IssueTrackingError.notImplemented("Jira")
    }

    package func syncBackStatus(mapping: IssueMapping, task: AgentTask, config: IssueTrackingConfig) async throws {
        throw IssueTrackingError.notImplemented("Jira")
    }
}
