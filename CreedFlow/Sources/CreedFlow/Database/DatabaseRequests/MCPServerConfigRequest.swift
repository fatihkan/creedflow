import Foundation
import GRDB
import Combine

/// Observable store for MCP server configurations
@Observable
final class MCPServerConfigStore {
    private(set) var configs: [MCPServerConfig] = []
    private var cancellable: AnyCancellable?

    func observe(in dbQueue: DatabaseQueue) {
        cancellable = ValueObservation
            .tracking { db in
                try MCPServerConfig
                    .order(Column("name").asc)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] in self?.configs = $0 }
            )
    }
}

// MARK: - Query Helpers

extension MCPServerConfig {
    /// Fetch all enabled configs by their names
    static func fetchEnabled(names: [String], in db: Database) throws -> [MCPServerConfig] {
        try MCPServerConfig
            .filter(names.contains(Column("name")))
            .filter(Column("isEnabled") == true)
            .fetchAll(db)
    }

    /// Fetch all enabled configs
    static func fetchAllEnabled(in db: Database) throws -> [MCPServerConfig] {
        try MCPServerConfig
            .filter(Column("isEnabled") == true)
            .order(Column("name").asc)
            .fetchAll(db)
    }
}
