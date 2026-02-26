import SwiftUI

struct GitCommitRowView: View {
    let commit: GitCommit
    let currentBranch: String

    var body: some View {
        HStack(spacing: 8) {
            // Decoration badges
            ForEach(commit.decorations, id: \.name) { decoration in
                decorationBadge(decoration)
            }

            // Commit message
            Text(commit.message)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            // Short hash (monospace, selectable)
            Text(commit.shortHash)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            // Author
            Text(commit.author)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 100, alignment: .trailing)

            // Relative date
            Text(commit.date, style: .relative)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.trailing, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Decoration Badge

    @ViewBuilder
    private func decorationBadge(_ decoration: GitDecoration) -> some View {
        HStack(spacing: 3) {
            if decoration.type == .head {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 11))
            }
            Text(decoration.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(branchColor(for: decoration).opacity(0.14))
        .foregroundStyle(branchColor(for: decoration))
        .clipShape(Capsule())
    }

    private func branchColor(for decoration: GitDecoration) -> Color {
        switch decoration.type {
        case .tag:
            return .forgeWarning
        case .remoteBranch:
            return .forgeNeutral
        case .head, .localBranch:
            return Color.gitBranchColor(for: decoration.name)
        }
    }
}
