import Foundation

// MARK: - Git Commit

package struct GitCommit: Identifiable, Equatable {
    package let id: String          // Full SHA hash
    package let shortHash: String   // First 7 chars
    package let parentIds: [String] // Parent hashes (>1 = merge commit)
    package let author: String
    package let date: Date
    package let message: String
    package let decorations: [GitDecoration]

    package var isMerge: Bool { parentIds.count > 1 }
}

// MARK: - Git Decoration

package struct GitDecoration: Equatable, Hashable {
    package let name: String
    package let type: DecorationType

    package enum DecorationType: Equatable, Hashable {
        case head
        case localBranch
        case remoteBranch
        case tag
    }
}

// MARK: - Git Graph Row (layout result)

package struct GitGraphRow: Identifiable {
    package let commit: GitCommit
    package let column: Int               // Lane index for this commit's dot
    package let activeLanes: Set<Int>     // Lanes with active lines passing through
    package let connections: [Connection] // Merge/branch curve connections

    package var id: String { commit.id }

    package struct Connection: Equatable {
        package let fromColumn: Int
        package let toColumn: Int
        package let type: ConnectionType
    }

    package enum ConnectionType: Equatable {
        case merge      // Incoming merge line (parent → child)
        case branch     // Outgoing branch line (child → parent)
    }
}

// MARK: - Git Graph Data (complete layout)

package struct GitGraphData {
    package let rows: [GitGraphRow]
    package let currentBranch: String
    package let maxColumns: Int
    package let allBranches: [String]

    package static let empty = GitGraphData(rows: [], currentBranch: "", maxColumns: 0, allBranches: [])
}
