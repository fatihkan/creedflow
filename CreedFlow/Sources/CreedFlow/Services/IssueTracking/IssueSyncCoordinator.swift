import Foundation
import GRDB
import os.log

/// Coordinates issue sync across providers. Dispatches to LinearSyncService or JiraSyncService.
package actor IssueSyncCoordinator {
    private let logger = Logger(subsystem: "com.creedflow", category: "IssueSyncCoordinator")
    private let dbQueue: DatabaseQueue
    private let linearService: LinearSyncService
    private let jiraService: JiraSyncService

    package init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        self.linearService = LinearSyncService(dbQueue: dbQueue)
        self.jiraService = JiraSyncService(dbQueue: dbQueue)
    }

    /// Import issues from the configured provider.
    package func importIssues(configId: UUID) async throws -> [IssueMapping] {
        let config = try await dbQueue.read { db in
            try IssueTrackingConfig.fetchOne(db, id: configId)
        }

        guard let config else {
            throw IssueTrackingError.configNotFound
        }

        switch config.provider {
        case .linear:
            return try await linearService.importIssues(config: config)
        case .jira:
            return try await jiraService.importIssues(config: config)
        }
    }

    /// Sync task completion status back to the external issue tracker (best-effort).
    package func syncBack(taskId: UUID) async throws {
        // Find all mappings for this task
        let mappingsAndConfigs: [(IssueMapping, IssueTrackingConfig)] = try await dbQueue.read { db in
            let mappings = try IssueMapping
                .filter(Column("taskId") == taskId)
                .fetchAll(db)

            return try mappings.compactMap { mapping in
                guard let config = try IssueTrackingConfig.fetchOne(db, id: mapping.configId) else {
                    return nil
                }
                return (mapping, config)
            }
        }

        guard !mappingsAndConfigs.isEmpty else { return }

        let task = try await dbQueue.read { db in
            try AgentTask.fetchOne(db, id: taskId)
        }
        guard let task else { return }

        for (mapping, config) in mappingsAndConfigs {
            guard config.isEnabled, config.syncBackEnabled else { continue }

            do {
                switch config.provider {
                case .linear:
                    try await linearService.syncBackStatus(mapping: mapping, task: task, config: config)
                case .jira:
                    try await jiraService.syncBackStatus(mapping: mapping, task: task, config: config)
                }
            } catch {
                logger.warning("Sync-back failed for \(mapping.externalIdentifier): \(error.localizedDescription)")
            }
        }
    }
}
