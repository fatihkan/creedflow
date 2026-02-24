import Foundation
import GRDB

/// Bridge between Creed database and MCP tool/resource handlers.
/// Provides the core data operations that MCP tools and resources use.
/// Uses `package` access so MCPServer target can use it without exposing internal model types publicly.
package final class MCPBridge: Sendable {
    package let dbQueue: DatabaseQueue

    package init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Project Operations

    package func createProject(name: String, description: String, techStack: String) throws -> Project {
        try dbQueue.write { db in
            var project = Project(name: name, description: description, techStack: techStack)
            try project.insert(db)
            return project
        }
    }

    package func getProject(id: UUID) throws -> Project? {
        try dbQueue.read { db in
            try Project.fetchOne(db, id: id)
        }
    }

    package func getAllProjects() throws -> [Project] {
        try dbQueue.read { db in
            try Project.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    package func getProjectStatus(id: UUID) throws -> ProjectStatusInfo? {
        try dbQueue.read { db in
            guard let project = try Project.fetchOne(db, id: id) else { return nil }

            let taskCount = try AgentTask
                .filter(Column("projectId") == id)
                .fetchCount(db)
            let completedCount = try AgentTask
                .filter(Column("projectId") == id)
                .filter(Column("status") == AgentTask.Status.passed.rawValue)
                .fetchCount(db)
            let failedCount = try AgentTask
                .filter(Column("projectId") == id)
                .filter(Column("status") == AgentTask.Status.failed.rawValue)
                .fetchCount(db)
            let inProgressCount = try AgentTask
                .filter(Column("projectId") == id)
                .filter(Column("status") == AgentTask.Status.inProgress.rawValue)
                .fetchCount(db)
            let totalCost = try Double.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(costUSD), 0) FROM costTracking WHERE projectId = ?",
                arguments: [id.uuidString]
            ) ?? 0

            return ProjectStatusInfo(
                project: project,
                totalTasks: taskCount,
                completedTasks: completedCount,
                failedTasks: failedCount,
                inProgressTasks: inProgressCount,
                totalCostUSD: totalCost
            )
        }
    }

    // MARK: - Task Operations

    package func enqueueTask(
        projectId: UUID,
        agentType: AgentTask.AgentType,
        title: String,
        description: String,
        priority: Int
    ) throws -> AgentTask {
        try dbQueue.write { db in
            var task = AgentTask(
                projectId: projectId,
                agentType: agentType,
                title: title,
                description: description,
                priority: priority
            )
            try task.insert(db)
            return task
        }
    }

    package func listTasks(projectId: UUID?, status: AgentTask.Status?, agentType: AgentTask.AgentType?) throws -> [AgentTask] {
        try dbQueue.read { db in
            var request = AgentTask.order(Column("priority").desc, Column("createdAt").asc)
            if let projectId {
                request = request.filter(Column("projectId") == projectId)
            }
            if let status {
                request = request.filter(Column("status") == status.rawValue)
            }
            if let agentType {
                request = request.filter(Column("agentType") == agentType.rawValue)
            }
            return try request.fetchAll(db)
        }
    }

    package func cancelTask(id: UUID) throws -> Bool {
        try dbQueue.write { db in
            guard var task = try AgentTask.fetchOne(db, id: id) else { return false }
            guard task.status == .queued || task.status == .inProgress else { return false }
            task.status = .cancelled
            task.updatedAt = Date()
            try task.update(db)
            return true
        }
    }

    package func retryTask(id: UUID) throws -> Bool {
        try dbQueue.write { db in
            guard var task = try AgentTask.fetchOne(db, id: id) else { return false }
            guard task.status == .failed || task.status == .needsRevision else { return false }
            task.status = .queued
            task.errorMessage = nil
            task.result = nil
            task.retryCount += 1
            task.updatedAt = Date()
            try task.update(db)
            return true
        }
    }

    // MARK: - Log Operations

    package func getAgentLogs(taskId: UUID, limit: Int = 100) throws -> [AgentLog] {
        try dbQueue.read { db in
            try AgentLog
                .filter(Column("taskId") == taskId)
                .order(Column("createdAt").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Cost Operations

    package func getCostSummary() throws -> CostSummaryInfo {
        try dbQueue.read { db in
            let totalCost = try Double.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(costUSD), 0) FROM costTracking"
            ) ?? 0
            let totalInputTokens = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(inputTokens), 0) FROM costTracking"
            ) ?? 0
            let totalOutputTokens = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(outputTokens), 0) FROM costTracking"
            ) ?? 0
            let recordCount = try CostTracking.fetchCount(db)

            return CostSummaryInfo(
                totalCostUSD: totalCost,
                totalInputTokens: totalInputTokens,
                totalOutputTokens: totalOutputTokens,
                totalInvocations: recordCount
            )
        }
    }

    // MARK: - Queue Status

    package func getQueueStatus() throws -> QueueStatusInfo {
        try dbQueue.read { db in
            let queued = try AgentTask
                .filter(Column("status") == AgentTask.Status.queued.rawValue)
                .order(Column("priority").desc, Column("createdAt").asc)
                .fetchAll(db)
            let inProgress = try AgentTask
                .filter(Column("status") == AgentTask.Status.inProgress.rawValue)
                .fetchAll(db)
            return QueueStatusInfo(queuedTasks: queued, inProgressTasks: inProgress)
        }
    }
}

// MARK: - Info Types

package struct ProjectStatusInfo: Sendable {
    package let project: Project
    package let totalTasks: Int
    package let completedTasks: Int
    package let failedTasks: Int
    package let inProgressTasks: Int
    package let totalCostUSD: Double
}

package struct CostSummaryInfo: Sendable {
    package let totalCostUSD: Double
    package let totalInputTokens: Int
    package let totalOutputTokens: Int
    package let totalInvocations: Int
}

package struct QueueStatusInfo: Sendable {
    package let queuedTasks: [AgentTask]
    package let inProgressTasks: [AgentTask]
}
