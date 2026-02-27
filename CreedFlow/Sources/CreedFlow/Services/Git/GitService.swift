import Foundation

/// Wrapper around `git` CLI for repository operations.
actor GitService {
    private let gitPath: String

    init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    /// Initialize a new git repository
    func initRepo(at path: String) async throws {
        try await run(["init"], in: path)
    }

    /// Create and checkout a new branch
    func createBranch(_ name: String, in path: String) async throws {
        try await run(["checkout", "-b", name], in: path)
    }

    /// Checkout an existing branch
    func checkout(_ branch: String, in path: String) async throws {
        try await run(["checkout", branch], in: path)
    }

    /// Stage all changes
    func addAll(in path: String) async throws {
        try await run(["add", "-A"], in: path)
    }

    /// Commit staged changes
    func commit(message: String, in path: String) async throws {
        try await run(["commit", "-m", message], in: path)
    }

    /// Get current branch name
    func currentBranch(in path: String) async throws -> String {
        let output = try await run(["branch", "--show-current"], in: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get diff of current changes
    func diff(in path: String) async throws -> String {
        try await run(["diff"], in: path)
    }

    /// Get diff between two branches
    func diff(from base: String, to head: String, in path: String) async throws -> String {
        try await run(["diff", "\(base)...\(head)"], in: path)
    }

    /// Get status
    func status(in path: String) async throws -> String {
        try await run(["status", "--porcelain"], in: path)
    }

    /// Get log (last N commits)
    func log(count: Int = 10, in path: String) async throws -> String {
        try await run(["log", "--oneline", "-\(count)"], in: path)
    }

    /// Check if a branch exists locally
    func branchExists(_ name: String, in path: String) async throws -> Bool {
        let output = try await run(["branch", "--list", name], in: path)
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Merge a branch into the current branch
    func merge(_ branch: String, message: String? = nil, in path: String) async throws {
        var args = ["merge", branch]
        if let message {
            args += ["-m", message]
        }
        try await run(args, in: path)
    }

    /// Fetch latest from remote
    func fetch(in path: String) async throws {
        try await run(["fetch", "origin"], in: path)
    }

    /// Check if there are uncommitted changes (staged or unstaged)
    func hasChanges(in path: String) async throws -> Bool {
        let output = try await run(["status", "--porcelain"], in: path)
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Delete a local branch (force)
    func deleteBranch(_ name: String, in path: String) async throws {
        try await run(["branch", "-D", name], in: path)
    }

    /// Get the HEAD commit hash (short)
    func headCommitHash(in path: String) async throws -> String {
        let output = try await run(["rev-parse", "--short", "HEAD"], in: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get structured log with all branches for graph visualization
    func structuredLog(count: Int = 200, in path: String) async throws -> String {
        try await run(
            ["log", "--all", "--format=%H|%P|%D|%an|%at|%s", "-\(count)"],
            in: path
        )
    }

    /// Get all branch names (local + remote)
    func allBranches(in path: String) async throws -> [String] {
        let output = try await run(
            ["branch", "-a", "--format=%(refname:short)"],
            in: path
        )
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    @discardableResult
    private func run(_ arguments: [String], in directory: String) async throws -> String {
        try await Process.run(
            gitPath,
            arguments: arguments,
            currentDirectory: directory
        )
    }
}
