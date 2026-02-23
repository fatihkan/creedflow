import Foundation

/// Wrapper around `gh` CLI for GitHub operations (PRs, issues, etc.)
actor GitHubService {
    private let ghPath: String

    init(ghPath: String? = nil) {
        self.ghPath = ghPath ?? Self.resolveGHPath()
    }

    /// Search common install paths for the `gh` binary
    private static func resolveGHPath() -> String {
        let candidates = [
            "/usr/local/bin/gh",
            "/opt/homebrew/bin/gh",
            "/usr/bin/gh",
            "/opt/local/bin/gh"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Fallback: rely on PATH via /usr/bin/env
        return "/usr/bin/env"
    }

    /// Build arguments — if using /usr/bin/env, prefix with "gh"
    private func buildArgs(_ args: [String]) -> (executable: String, arguments: [String]) {
        if ghPath == "/usr/bin/env" {
            return (ghPath, ["gh"] + args)
        }
        return (ghPath, args)
    }

    /// Create a pull request
    func createPR(
        title: String,
        body: String,
        base: String = "main",
        head: String,
        in path: String
    ) async throws -> PRInfo {
        let (exe, args) = buildArgs([
            "pr", "create",
            "--title", title,
            "--body", body,
            "--base", base,
            "--head", head,
            "--json", "number,url"
        ])
        let output = try await Process.run(exe, arguments: args, currentDirectory: path)

        guard let data = output.data(using: .utf8),
              let json = try? JSONDecoder().decode(PRInfo.self, from: data) else {
            // gh pr create outputs the URL on success
            let url = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return PRInfo(number: 0, url: url)
        }
        return json
    }

    /// Get PR status
    func prStatus(number: Int, in path: String) async throws -> String {
        let (exe, args) = buildArgs(["pr", "view", String(number), "--json", "state,statusCheckRollup"])
        return try await Process.run(exe, arguments: args, currentDirectory: path)
    }

    /// Merge a PR
    func mergePR(number: Int, method: MergeMethod = .squash, in path: String) async throws {
        let (exe, args) = buildArgs(["pr", "merge", String(number), "--\(method.rawValue)"])
        try await Process.run(exe, arguments: args, currentDirectory: path)
    }

    /// Push current branch to remote
    func push(branch: String, in path: String) async throws {
        try await Process.run(
            "/usr/bin/git",
            arguments: ["push", "-u", "origin", branch],
            currentDirectory: path
        )
    }

    struct PRInfo: Codable {
        let number: Int
        let url: String
    }

    enum MergeMethod: String {
        case merge
        case squash
        case rebase
    }
}
