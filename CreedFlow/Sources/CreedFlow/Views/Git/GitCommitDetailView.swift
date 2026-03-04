import SwiftUI

struct GitCommitDetailView: View {
    let commit: GitCommit
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .foregroundStyle(.forgeAmber)
                Text("Commit Detail")
                    .font(.system(.subheadline, weight: .semibold))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Hash
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HASH")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(commit.id)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.forgeAmber)
                            .textSelection(.enabled)
                    }

                    // Message
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MESSAGE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(commit.message)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                    }

                    // Author
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text(commit.author)
                            .font(.system(size: 12))
                    }

                    // Date
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text(commit.date, format: .dateTime)
                            .font(.system(size: 12))
                    }

                    // Parents
                    if !commit.parentIds.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(commit.parentIds.count > 1 ? "PARENTS" : "PARENT")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            ForEach(commit.parentIds, id: \.self) { parent in
                                Text(String(parent.prefix(7)))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            if commit.isMerge {
                                Text("Merge commit")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.forgeWarning)
                                    .padding(.top, 2)
                            }
                        }
                    }

                    // Decorations
                    if !commit.decorations.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Text("REFS")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            FlowLayout(spacing: 4) {
                                ForEach(commit.decorations, id: \.name) { decoration in
                                    Text(decoration.name)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(decorationColor(decoration).opacity(0.14))
                                        .foregroundStyle(decorationColor(decoration))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func decorationColor(_ decoration: GitDecoration) -> Color {
        switch decoration.type {
        case .head: return .forgeAmber
        case .tag: return .forgeWarning
        case .remoteBranch: return .forgeInfo
        case .localBranch: return .forgeSuccess
        }
    }
}

/// Simple flow layout for wrapping badges
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = y + rowHeight
        }

        return ArrangeResult(size: CGSize(width: maxWidth, height: totalHeight), positions: positions)
    }
}
