import SwiftUI

struct PromptVersionDiffView: View {
    let oldVersion: PromptVersion
    let newVersion: PromptVersion
    @Environment(\.dismiss) private var dismiss

    private var diffResult: (old: [DiffLine], new: [DiffLine]) {
        computeDiff(
            old: oldVersion.content.components(separatedBy: "\n"),
            new: newVersion.content.components(separatedBy: "\n")
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Version Diff")
                    .font(.title3.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            // Column headers
            HStack(spacing: 0) {
                Text("v\(oldVersion.version) — \(oldVersion.title)")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                Divider()
                Text("v\(newVersion.version) — \(newVersion.title)")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            .frame(height: 28)
            .background(.quaternary.opacity(0.3))

            Divider()

            // Diff panels
            let result = diffResult
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(result.old.enumerated()), id: \.offset) { _, line in
                            diffLineView(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(result.new.enumerated()), id: \.offset) { _, line in
                            diffLineView(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 700, height: 500)
    }

    @ViewBuilder
    private func diffLineView(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            Text(line.text)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.kind.backgroundColor)
    }
}

// MARK: - Diff Types

enum DiffLineKind {
    case unchanged
    case added
    case removed
    case blank
}

extension DiffLineKind {
    var backgroundColor: some ShapeStyle {
        switch self {
        case .unchanged: return AnyShapeStyle(.clear)
        case .added: return AnyShapeStyle(Color(red: 0.18, green: 0.75, blue: 0.48).opacity(0.12))
        case .removed: return AnyShapeStyle(Color(red: 0.92, green: 0.28, blue: 0.30).opacity(0.12))
        case .blank: return AnyShapeStyle(.quaternary.opacity(0.2))
        }
    }
}

struct DiffLine {
    let text: String
    let kind: DiffLineKind
}

// MARK: - LCS Diff

func computeDiff(old: [String], new: [String]) -> (old: [DiffLine], new: [DiffLine]) {
    let m = old.count
    let n = new.count

    // Build LCS table
    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in 1...max(m, 1) {
        guard i <= m else { break }
        for j in 1...max(n, 1) {
            guard j <= n else { break }
            if old[i - 1] == new[j - 1] {
                dp[i][j] = dp[i - 1][j - 1] + 1
            } else {
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
            }
        }
    }

    // Backtrack to find diff
    var oldLines: [DiffLine] = []
    var newLines: [DiffLine] = []
    var i = m, j = n

    var oldReversed: [DiffLine] = []
    var newReversed: [DiffLine] = []

    while i > 0 || j > 0 {
        if i > 0 && j > 0 && old[i - 1] == new[j - 1] {
            oldReversed.append(DiffLine(text: old[i - 1], kind: .unchanged))
            newReversed.append(DiffLine(text: new[j - 1], kind: .unchanged))
            i -= 1
            j -= 1
        } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
            oldReversed.append(DiffLine(text: "", kind: .blank))
            newReversed.append(DiffLine(text: new[j - 1], kind: .added))
            j -= 1
        } else if i > 0 {
            oldReversed.append(DiffLine(text: old[i - 1], kind: .removed))
            newReversed.append(DiffLine(text: "", kind: .blank))
            i -= 1
        }
    }

    oldLines = oldReversed.reversed()
    newLines = newReversed.reversed()

    return (oldLines, newLines)
}
