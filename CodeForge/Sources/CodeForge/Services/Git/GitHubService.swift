import Foundation

/// Wrapper around `gh` CLI for GitHub operations (PRs, issues, etc.)
actor GitHubService {
    private let ghPath: String

    init(ghPath: String = "/usr/local/bin/gh") {
        self.ghPath = ghPath
    }

    /// Create a pull request
    func createPR(
        title: String,
        body: String,
        base: String = "main",
        head: String,
        in path: String
    ) async throws -> PRInfo {
        let output = try await Process.run(
            ghPath,
            arguments: [
                "pr", "create",
                "--title", title,
                "--body", body,
                "--base", base,
                "--head", head,
                "--json", "number,url"
            ],
            currentDirectory: path
        )

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
        try await Process.run(
            ghPath,
            arguments: ["pr", "view", String(number), "--json", "state,statusCheckRollup"],
            currentDirectory: path
        )
    }

    /// Merge a PR
    func mergePR(number: Int, method: MergeMethod = .squash, in path: String) async throws {
        try await Process.run(
            ghPath,
            arguments: ["pr", "merge", String(number), "--\(method.rawValue)"],
            currentDirectory: path
        )
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
