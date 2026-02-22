import Foundation
import GRDB

/// SQLite-backed priority queue for agent tasks.
/// Dequeues tasks atomically: SELECT + UPDATE in a single transaction.
actor TaskQueue {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Atomically dequeue the next ready task (highest priority, oldest first).
    /// A task is "ready" when:
    /// - status == 'queued'
    /// - all dependencies have status == 'passed'
    func dequeue() async throws -> AgentTask? {
        try await dbQueue.write { db in
            // Find the next ready task
            let task = try AgentTask.fetchOne(db, sql: """
                SELECT t.* FROM agentTask t
                WHERE t.status = 'queued'
                  AND NOT EXISTS (
                    SELECT 1 FROM taskDependency td
                    JOIN agentTask dep ON dep.id = td.dependsOnTaskId
                    WHERE td.taskId = t.id AND dep.status != 'passed'
                  )
                ORDER BY t.priority DESC, t.createdAt ASC
                LIMIT 1
                """)

            guard var task else { return nil }

            // Atomically mark as in-progress
            task.status = .inProgress
            task.startedAt = Date()
            task.updatedAt = Date()
            try task.update(db)

            return task
        }
    }

    /// Re-queue a failed task for retry
    func requeue(_ task: AgentTask) async throws {
        try await dbQueue.write { db in
            var updated = task
            updated.status = .queued
            updated.retryCount += 1
            updated.updatedAt = Date()
            updated.startedAt = nil
            try updated.update(db)
        }
    }

    /// Mark a task as failed
    func fail(_ task: AgentTask, error: String) async throws {
        try await dbQueue.write { db in
            var updated = task
            updated.status = .failed
            updated.errorMessage = error
            updated.updatedAt = Date()
            updated.completedAt = Date()
            try updated.update(db)
        }
    }

    /// Get count of queued tasks
    func queuedCount() async throws -> Int {
        try await dbQueue.read { db in
            try AgentTask
                .filter(Column("status") == AgentTask.Status.queued.rawValue)
                .fetchCount(db)
        }
    }

    /// Get count of in-progress tasks
    func activeCount() async throws -> Int {
        try await dbQueue.read { db in
            try AgentTask
                .filter(Column("status") == AgentTask.Status.inProgress.rawValue)
                .fetchCount(db)
        }
    }

    /// Recovery: re-queue or fail tasks that were in-progress when app crashed
    func recoverOrphanedTasks() async throws {
        try await dbQueue.write { db in
            let orphaned = try AgentTask
                .filter(Column("status") == AgentTask.Status.inProgress.rawValue)
                .fetchAll(db)

            for var task in orphaned {
                if task.retryCount < task.maxRetries {
                    task.status = .queued
                    task.retryCount += 1
                } else {
                    task.status = .failed
                    task.errorMessage = "Orphaned after app restart (exceeded max retries)"
                    task.completedAt = Date()
                }
                task.updatedAt = Date()
                try task.update(db)
            }
        }
    }
}
