import Foundation
import GRDB
import Combine

/// Observable store for tasks
@Observable
final class TaskStore {
    private(set) var tasks: [AgentTask] = []
    private var cancellable: AnyCancellable?

    func observe(projectId: UUID? = nil, in dbQueue: DatabaseQueue) {
        cancellable = ValueObservation
            .tracking { db in
                var request = AgentTask.order(Column("priority").desc, Column("createdAt").asc)
                if let projectId {
                    request = request.filter(Column("projectId") == projectId)
                }
                return try request.fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] in self?.tasks = $0 }
            )
    }
}

/// Observable store for reviews
@Observable
final class ReviewStore {
    private(set) var reviews: [Review] = []
    private var cancellable: AnyCancellable?

    func observe(taskId: UUID, in dbQueue: DatabaseQueue) {
        cancellable = ValueObservation
            .tracking { db in
                try Review
                    .filter(Column("taskId") == taskId)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] in self?.reviews = $0 }
            )
    }
}

/// Observable store for agent logs
@Observable
final class AgentLogStore {
    private(set) var logs: [AgentLog] = []
    private var cancellable: AnyCancellable?

    func observe(taskId: UUID, in dbQueue: DatabaseQueue) {
        cancellable = ValueObservation
            .tracking { db in
                try AgentLog
                    .filter(Column("taskId") == taskId)
                    .order(Column("createdAt").asc)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] in self?.logs = $0 }
            )
    }
}
