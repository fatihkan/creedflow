import Foundation
import GRDB
import Combine

/// Info for displaying a project with computed stats
struct ProjectInfo: Equatable {
    var project: Project
    var taskCount: Int
    var completedTaskCount: Int
    var totalCostUSD: Double
}

/// Observable store that publishes lists of projects using GRDB ValueObservation.
@Observable
final class ProjectStore {
    private(set) var projects: [Project] = []
    private var cancellable: AnyCancellable?

    func observe(in dbQueue: DatabaseQueue) {
        cancellable = ValueObservation
            .tracking { db in
                try Project.order(Column("updatedAt").desc).fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] in self?.projects = $0 }
            )
    }
}

/// Observable store for a single project's detail info
@Observable
final class ProjectDetailStore {
    private(set) var info: ProjectInfo?
    private var cancellable: AnyCancellable?

    func observe(projectId: UUID, in dbQueue: DatabaseQueue) {
        cancellable = ValueObservation
            .tracking { db in
                guard let project = try Project.fetchOne(db, id: projectId) else {
                    return nil as ProjectInfo?
                }
                let taskCount = try AgentTask
                    .filter(Column("projectId") == projectId)
                    .fetchCount(db)
                let completedTaskCount = try AgentTask
                    .filter(Column("projectId") == projectId)
                    .filter(Column("status") == AgentTask.Status.passed.rawValue)
                    .fetchCount(db)
                let totalCostUSD = try Double.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(costUSD), 0) FROM costTracking WHERE projectId = ?",
                    arguments: [projectId.uuidString]
                ) ?? 0
                return ProjectInfo(
                    project: project,
                    taskCount: taskCount,
                    completedTaskCount: completedTaskCount,
                    totalCostUSD: totalCostUSD
                )
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] in self?.info = $0 }
            )
    }
}
