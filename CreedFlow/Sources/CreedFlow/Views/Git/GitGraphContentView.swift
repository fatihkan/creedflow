import SwiftUI

struct GitGraphContentView: View {
    let graphData: GitGraphData
    let maxColumns: Int
    var selectedCommitId: String? = nil
    var onSelectCommit: ((GitCommit) -> Void)? = nil

    private let laneWidth: CGFloat = 24
    private let rowHeight: CGFloat = 36
    private let dotRadius: CGFloat = 5

    private var graphWidth: CGFloat {
        CGFloat(max(maxColumns, 1)) * laneWidth + laneWidth
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(spacing: 0) {
                ForEach(Array(graphData.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 0) {
                        // Left: graph canvas
                        Canvas { context, size in
                            drawRow(context: &context, row: row, index: index, size: size)
                        }
                        .frame(width: graphWidth, height: rowHeight)

                        // Right: commit info
                        GitCommitRowView(
                            commit: row.commit,
                            currentBranch: graphData.currentBranch
                        )

                        Spacer(minLength: 0)
                    }
                    .frame(height: rowHeight)
                    .background(selectedCommitId == row.commit.id ? Color.accentColor.opacity(0.08) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectCommit?(row.commit)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Canvas Drawing

    private func drawRow(context: inout GraphicsContext, row: GitGraphRow, index: Int, size: CGSize) {
        let centerY = size.height / 2
        let commitX = xForLane(row.column)

        // 1. Draw active lane lines (vertical through-lines)
        for lane in row.activeLanes {
            let x = xForLane(lane)
            let color = colorForLane(lane)

            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: 2)
        }

        // 2. Draw the commit's own lane line
        let commitColor = colorForLane(row.column)

        // Line from top to center
        var topLine = Path()
        topLine.move(to: CGPoint(x: commitX, y: 0))
        topLine.addLine(to: CGPoint(x: commitX, y: centerY))
        context.stroke(topLine, with: .color(commitColor.opacity(0.5)), lineWidth: 2)

        // Line from center to bottom (if has parents)
        if !row.commit.parentIds.isEmpty {
            var bottomLine = Path()
            bottomLine.move(to: CGPoint(x: commitX, y: centerY))
            bottomLine.addLine(to: CGPoint(x: commitX, y: size.height))
            context.stroke(bottomLine, with: .color(commitColor.opacity(0.5)), lineWidth: 2)
        }

        // 3. Draw merge/branch connections (Bezier curves)
        for connection in row.connections {
            let fromX = xForLane(connection.fromColumn)
            let toX = xForLane(connection.toColumn)
            let curveColor = colorForLane(connection.fromColumn)

            var curve = Path()
            curve.move(to: CGPoint(x: fromX, y: size.height))
            curve.addCurve(
                to: CGPoint(x: toX, y: centerY),
                control1: CGPoint(x: fromX, y: centerY + size.height * 0.3),
                control2: CGPoint(x: toX, y: centerY + size.height * 0.1)
            )
            context.stroke(curve, with: .color(curveColor.opacity(0.6)), lineWidth: 2)
        }

        // 4. Draw commit dot
        if row.commit.isMerge {
            // Merge commit: ring (hollow circle)
            let rect = CGRect(
                x: commitX - dotRadius,
                y: centerY - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.stroke(Path(ellipseIn: rect), with: .color(commitColor), lineWidth: 2)
            // Inner fill with background
            let innerRect = rect.insetBy(dx: 2, dy: 2)
            context.fill(Path(ellipseIn: innerRect), with: .color(Color(nsColor: .windowBackgroundColor)))
        } else {
            // Normal commit: filled circle
            let rect = CGRect(
                x: commitX - dotRadius,
                y: centerY - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(commitColor))
        }
    }

    // MARK: - Helpers

    private func xForLane(_ lane: Int) -> CGFloat {
        CGFloat(lane) * laneWidth + laneWidth / 2 + 8
    }

    /// Cycle through a color palette based on lane index.
    private func colorForLane(_ lane: Int) -> Color {
        let palette: [Color] = [
            .forgeSuccess,   // green (main)
            .forgeInfo,      // blue (staging)
            .forgeAmber,     // amber (dev)
            .purple,
            .teal,
            .orange,
            .pink,
            .indigo,
            .mint,
            .cyan
        ]
        return palette[lane % palette.count]
    }
}
