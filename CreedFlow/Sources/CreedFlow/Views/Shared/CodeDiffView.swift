import SwiftUI

// MARK: - Data Types

enum DiffLineType { case added, removed, context }

struct DiffLineItem: Identifiable {
    let id = UUID()
    let type: DiffLineType
    let content: String
    let oldLineNo: Int?
    let newLineNo: Int?
}

struct DiffHunkItem {
    let header: String
    var lines: [DiffLineItem]
}

struct DiffFileItem {
    let name: String
    var hunks: [DiffHunkItem]
}

// MARK: - Main View

/// Detects and renders unified diff output with syntax-highlighted additions and removals.
struct CodeDiffView: View {
    let text: String

    /// Returns true if the text contains a unified diff.
    static func containsUnifiedDiff(_ text: String) -> Bool {
        text.contains("--- a/") && text.contains("+++ b/")
    }

    var body: some View {
        let files = DiffParser.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                DiffFileView(file: file)
            }
        }
    }
}

// MARK: - Sub-Views

private struct DiffFileView: View {
    let file: DiffFileItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            fileHeader
            ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                DiffHunkView(hunk: hunk)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var fileHeader: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
            Text(file.name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
    }
}

private struct DiffHunkView: View {
    let hunk: DiffHunkItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.blue.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.03))

            ForEach(hunk.lines) { line in
                DiffLineView(line: line)
            }
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLineItem

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldLineNo.map { String($0) } ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.tertiary)

            Text(line.newLineNo.map { String($0) } ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.tertiary)

            Text(linePrefix)
                .frame(width: 16, alignment: .center)
                .foregroundStyle(lineColor)

            Text(line.content)
                .foregroundStyle(lineColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 4)
        .padding(.vertical, 0.5)
        .background(lineBg)
    }

    private var linePrefix: String {
        switch line.type {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private var lineColor: Color {
        switch line.type {
        case .added: return .green
        case .removed: return .red
        case .context: return .secondary
        }
    }

    private var lineBg: Color {
        switch line.type {
        case .added: return .green.opacity(0.06)
        case .removed: return .red.opacity(0.06)
        case .context: return .clear
        }
    }
}

// MARK: - Parser

enum DiffParser {
    static func parse(_ text: String) -> [DiffFileItem] {
        var files: [DiffFileItem] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            if lines[i].hasPrefix("--- a/") {
                let fileName = String(lines[i].dropFirst(6))
                i += 2

                var hunks: [DiffHunkItem] = []
                while i < lines.count && !lines[i].hasPrefix("--- a/") {
                    if lines[i].hasPrefix("@@") {
                        let header = lines[i]
                        var oldLine = 1
                        var newLine = 1
                        if let range = header.range(of: #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#, options: .regularExpression) {
                            let nums = header[range]
                                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                                .filter { !$0.isEmpty }
                            if nums.count >= 2 {
                                oldLine = Int(nums[0]) ?? 1
                                newLine = Int(nums[1]) ?? 1
                            }
                        }
                        i += 1

                        var hunkLines: [DiffLineItem] = []
                        while i < lines.count && !lines[i].hasPrefix("@@") && !lines[i].hasPrefix("--- a/") {
                            let line = lines[i]
                            if line.hasPrefix("+") {
                                hunkLines.append(DiffLineItem(type: .added, content: String(line.dropFirst()), oldLineNo: nil, newLineNo: newLine))
                                newLine += 1
                            } else if line.hasPrefix("-") {
                                hunkLines.append(DiffLineItem(type: .removed, content: String(line.dropFirst()), oldLineNo: oldLine, newLineNo: nil))
                                oldLine += 1
                            } else if line.hasPrefix(" ") || line.isEmpty {
                                let content = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                                hunkLines.append(DiffLineItem(type: .context, content: content, oldLineNo: oldLine, newLineNo: newLine))
                                oldLine += 1
                                newLine += 1
                            } else {
                                i += 1
                                continue
                            }
                            i += 1
                        }
                        hunks.append(DiffHunkItem(header: header, lines: hunkLines))
                    } else {
                        i += 1
                    }
                }
                files.append(DiffFileItem(name: fileName, hunks: hunks))
            } else {
                i += 1
            }
        }
        return files
    }
}
