import Foundation

/// Assigns lane (column) positions to commits for visual graph rendering.
/// Walks commits top-to-bottom (newest → oldest), tracking which lanes
/// are reserved for which commit hashes.
enum GitGraphLayoutEngine {

    static func layout(commits: [GitCommit]) -> GitGraphData {
        guard !commits.isEmpty else { return .empty }

        // lanes[i] = hash that lane i is waiting for (or nil if free)
        var lanes: [String?] = []
        var rows: [GitGraphRow] = []
        var maxColumns = 0

        for commit in commits {
            // 1. Find which lane is expecting this commit
            let existingLane = lanes.firstIndex(where: { $0 == commit.id })
            let column: Int

            if let lane = existingLane {
                column = lane
            } else {
                // No lane waiting — find first free lane or append new one
                if let free = lanes.firstIndex(where: { $0 == nil }) {
                    column = free
                } else {
                    column = lanes.count
                    lanes.append(nil)
                }
            }

            // 2. This lane is now consumed
            lanes[column] = nil

            // 3. Assign parents to lanes
            var connections: [GitGraphRow.Connection] = []

            for (i, parentId) in commit.parentIds.enumerated() {
                if i == 0 {
                    // First parent continues in same lane
                    lanes[column] = parentId
                } else {
                    // Additional parents (merge sources) — find existing lane or allocate
                    let parentLane = lanes.firstIndex(where: { $0 == parentId })
                    if let lane = parentLane {
                        // Parent already tracked in another lane — draw merge curve
                        connections.append(GitGraphRow.Connection(
                            fromColumn: lane,
                            toColumn: column,
                            type: .merge
                        ))
                    } else {
                        // Allocate new lane for this parent
                        if let free = lanes.firstIndex(where: { $0 == nil }) {
                            lanes[free] = parentId
                            connections.append(GitGraphRow.Connection(
                                fromColumn: free,
                                toColumn: column,
                                type: .branch
                            ))
                        } else {
                            let newLane = lanes.count
                            lanes.append(parentId)
                            connections.append(GitGraphRow.Connection(
                                fromColumn: newLane,
                                toColumn: column,
                                type: .branch
                            ))
                        }
                    }
                }
            }

            // 4. Compute active lanes (non-nil)
            let activeLanes = Set(lanes.indices.filter { lanes[$0] != nil })

            // 5. Trim trailing nil lanes
            while lanes.last == nil && !lanes.isEmpty {
                lanes.removeLast()
            }

            maxColumns = max(maxColumns, lanes.count, column + 1)

            rows.append(GitGraphRow(
                commit: commit,
                column: column,
                activeLanes: activeLanes,
                connections: connections
            ))
        }

        // Collect all branch names from decorations
        let allDecorations = commits.flatMap { $0.decorations }
        let branchNames = allDecorations
            .filter { $0.type == .localBranch || $0.type == .head }
            .map { $0.name }
        let allBranches = Array(Set(branchNames)).sorted()

        let headDecoration = commits.first?.decorations.first(where: { $0.type == .head })
        let currentBranch = headDecoration?.name ?? ""

        return GitGraphData(
            rows: rows,
            currentBranch: currentBranch,
            maxColumns: maxColumns,
            allBranches: allBranches
        )
    }
}
