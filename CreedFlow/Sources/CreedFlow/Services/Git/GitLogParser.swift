import Foundation

/// Parses `git log` structured output into `GitCommit` models.
enum GitLogParser {

    /// Parse output from `git log --all --format=%H|%P|%D|%an|%at|%s`
    static func parseLog(_ output: String) -> [GitCommit] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseLine(String($0)) }
    }

    private static func parseLine(_ line: String) -> GitCommit? {
        // Format: hash|parents|decorations|author|timestamp|subject
        let parts = line.split(separator: "|", maxSplits: 5, omittingEmptySubsequences: false)
        guard parts.count == 6 else { return nil }

        let hash = String(parts[0]).trimmingCharacters(in: .whitespaces)
        guard hash.count >= 7 else { return nil }

        let parentStr = String(parts[1]).trimmingCharacters(in: .whitespaces)
        let parentIds = parentStr.isEmpty
            ? []
            : parentStr.split(separator: " ").map { String($0) }

        let decorations = parseDecorations(String(parts[2]))
        let author = String(parts[3]).trimmingCharacters(in: .whitespaces)

        let timestampStr = String(parts[4]).trimmingCharacters(in: .whitespaces)
        let timestamp = TimeInterval(timestampStr) ?? 0
        let date = Date(timeIntervalSince1970: timestamp)

        let message = String(parts[5]).trimmingCharacters(in: .whitespaces)

        return GitCommit(
            id: hash,
            shortHash: String(hash.prefix(7)),
            parentIds: parentIds,
            author: author,
            date: date,
            message: message,
            decorations: decorations
        )
    }

    /// Parse decoration string like "HEAD -> dev, origin/dev, tag: v1.0"
    static func parseDecorations(_ raw: String) -> [GitDecoration] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        return trimmed
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .compactMap { part -> GitDecoration? in
                if part.hasPrefix("HEAD -> ") {
                    let branchName = String(part.dropFirst(8))
                    return GitDecoration(name: branchName, type: .head)
                } else if part == "HEAD" {
                    return GitDecoration(name: "HEAD", type: .head)
                } else if part.hasPrefix("tag: ") {
                    let tagName = String(part.dropFirst(5))
                    return GitDecoration(name: tagName, type: .tag)
                } else if part.contains("/") {
                    return GitDecoration(name: part, type: .remoteBranch)
                } else {
                    return GitDecoration(name: part, type: .localBranch)
                }
            }
    }
}
