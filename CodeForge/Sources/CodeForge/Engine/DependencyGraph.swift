import Foundation

/// Topological sort and cycle detection for task dependency graphs.
struct DependencyGraph {
    struct Edge: Hashable {
        let from: UUID  // task
        let to: UUID    // depends on
    }

    private var edges: Set<Edge> = []
    private var nodes: Set<UUID> = []

    mutating func addNode(_ id: UUID) {
        nodes.insert(id)
    }

    mutating func addDependency(task: UUID, dependsOn: UUID) {
        nodes.insert(task)
        nodes.insert(dependsOn)
        edges.insert(Edge(from: task, to: dependsOn))
    }

    /// Returns tasks in topological order (dependencies first).
    /// Throws if a cycle is detected.
    func topologicalSort() throws -> [UUID] {
        var inDegree: [UUID: Int] = [:]
        var adjacency: [UUID: [UUID]] = [:]

        for node in nodes {
            inDegree[node] = 0
            adjacency[node] = []
        }

        for edge in edges {
            // edge.to must complete before edge.from
            adjacency[edge.to, default: []].append(edge.from)
            inDegree[edge.from, default: 0] += 1
        }

        // Kahn's algorithm
        var queue = Array(nodes.filter { (inDegree[$0] ?? 0) == 0 })
        var sorted: [UUID] = []

        while !queue.isEmpty {
            let node = queue.removeFirst()
            sorted.append(node)

            for neighbor in adjacency[node] ?? [] {
                inDegree[neighbor, default: 0] -= 1
                if inDegree[neighbor] == 0 {
                    queue.append(neighbor)
                }
            }
        }

        if sorted.count != nodes.count {
            let cycleNodes = nodes.subtracting(sorted)
            throw DependencyError.cycleDetected(nodeIds: Array(cycleNodes))
        }

        return sorted
    }

    /// Check if adding a dependency would create a cycle
    func wouldCreateCycle(task: UUID, dependsOn: UUID) -> Bool {
        // If dependsOn (transitively) depends on task, adding this edge creates a cycle
        var visited: Set<UUID> = []
        var stack: [UUID] = [dependsOn]

        while let current = stack.popLast() {
            if current == task { return true }
            if visited.contains(current) { continue }
            visited.insert(current)

            for edge in edges where edge.from == current {
                stack.append(edge.to)
            }
        }

        return false
    }

    /// Get all tasks that are ready to execute (no unresolved dependencies)
    func readyTasks(completedTasks: Set<UUID>) -> [UUID] {
        nodes.filter { node in
            // Not already completed
            !completedTasks.contains(node) &&
            // All dependencies completed
            edges.filter { $0.from == node }
                .allSatisfy { completedTasks.contains($0.to) }
        }
    }
}

enum DependencyError: LocalizedError {
    case cycleDetected(nodeIds: [UUID])

    var errorDescription: String? {
        switch self {
        case .cycleDetected(let ids):
            return "Dependency cycle detected involving tasks: \(ids.map(\.uuidString).joined(separator: ", "))"
        }
    }
}
