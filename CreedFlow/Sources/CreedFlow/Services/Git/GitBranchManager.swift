import Foundation
import GRDB
import os.log

/// Manages the three-branch git strategy (dev → staging → main) for CreedFlow projects.
/// All git operations are best-effort — failures are logged but never fail the task.
actor GitBranchManager {
    private let gitService: GitService
    private let gitHubService: GitHubService
    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: "com.creedflow", category: "GitBranchManager")

    init(gitService: GitService, gitHubService: GitHubService, dbQueue: DatabaseQueue) {
        self.gitService = gitService
        self.gitHubService = gitHubService
        self.dbQueue = dbQueue
    }

    // MARK: - Branch Structure

    /// Idempotently ensure main, staging, and dev branches exist.
    /// Assumes the repo is already initialized with at least one commit on main.
    func ensureBranchStructure(in path: String) async throws {
        let currentBranch = try await gitService.currentBranch(in: path)

        // Make sure we're on main to branch from
        if currentBranch != "main" {
            try await gitService.checkout("main", in: path)
        }

        // Create staging if it doesn't exist
        if try await !gitService.branchExists("staging", in: path) {
            try await gitService.createBranch("staging", in: path)
            try await gitService.checkout("main", in: path)
        }

        // Create dev if it doesn't exist
        if try await !gitService.branchExists("dev", in: path) {
            try await gitService.createBranch("dev", in: path)
        } else {
            // Leave on dev as the working branch
            try await gitService.checkout("dev", in: path)
        }
    }

    // MARK: - Auto-Commit

    /// Commit convention prefix per agent type.
    private func commitPrefix(for agentType: AgentTask.AgentType) -> String {
        switch agentType {
        case .coder: return "feat"
        case .tester: return "test"
        case .devops: return "ops"
        case .analyzer: return "docs(analysis)"
        case .reviewer: return "docs(review)"
        case .contentWriter: return "content"
        case .designer: return "design"
        case .imageGenerator: return "asset(image)"
        case .videoEditor: return "asset(video)"
        case .monitor: return "chore(monitor)"
        case .publisher: return "chore(publish)"
        }
    }

    /// Stage all changes and commit if there are any. Returns the commit hash or nil if nothing to commit.
    func autoCommitIfNeeded(task: AgentTask, in path: String) async -> String? {
        do {
            try await gitService.addAll(in: path)
            guard try await gitService.hasChanges(in: path) else { return nil }

            let prefix = commitPrefix(for: task.agentType)
            let message = "\(prefix): \(task.title)\n\nTask: \(task.id)"
            try await gitService.commit(message: message, in: path)

            let hash = try await gitService.headCommitHash(in: path)
            logger.info("Auto-committed \(hash) for task \(task.id) [\(task.agentType.rawValue)]")
            return hash
        } catch {
            logger.error("Auto-commit failed for task \(task.id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Feature Branches

    /// Create a feature branch from dev for a coder task. Returns the branch name.
    func setupFeatureBranch(task: AgentTask, in path: String) async throws -> String {
        // Ensure we branch from dev
        try await gitService.checkout("dev", in: path)

        let sanitizedTitle = task.title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(30)
            .description
        let branchName = "feature/\(task.id.uuidString.prefix(8))-\(sanitizedTitle)"
        try await gitService.createBranch(branchName, in: path)

        // Update task with branch name
        try await dbQueue.write { db in
            var updated = task
            updated.branchName = branchName
            updated.updatedAt = Date()
            try updated.update(db)
        }

        logger.info("Created feature branch \(branchName) from dev")
        return branchName
    }

    /// After coder completes: commit, push, create PR targeting dev. Returns PR info or nil.
    func handleCoderBranchCompletion(task: AgentTask, in path: String) async -> GitHubService.PRInfo? {
        guard let branchName = task.branchName else {
            logger.warning("Coder task \(task.id) has no branch name — skipping PR creation")
            return nil
        }

        do {
            // Commit any remaining changes on the feature branch
            try await gitService.addAll(in: path)
            let status = try await gitService.status(in: path)
            if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await gitService.commit(
                    message: "feat: \(task.title)\n\nTask: \(task.id)",
                    in: path
                )
            }

            // Push feature branch
            try await gitHubService.push(branch: branchName, in: path)

            // Create PR targeting dev (not main)
            let pr = try await gitHubService.createPR(
                title: task.title,
                body: "Automated by CreedFlow\n\nTask: \(task.id)\n\n\(task.description)",
                base: "dev",
                head: branchName,
                in: path
            )

            // Store PR number on task
            try await dbQueue.write { db in
                var updated = task
                updated.prNumber = pr.number
                updated.updatedAt = Date()
                try updated.update(db)
            }

            logger.info("Created PR #\(pr.number) for \(branchName) → dev")
            return pr
        } catch {
            logger.error("Coder branch completion failed for \(task.id): \(error.localizedDescription)")
            try? await logError(taskId: task.id, agent: task.agentType, message: "Git/PR error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Merge & Promotion

    /// Merge a feature PR into dev (squash merge).
    func mergeFeatureToDev(prNumber: Int, in path: String) async {
        do {
            try await gitHubService.mergePR(number: prNumber, method: .squash, in: path)
            // Update local dev branch
            try await gitService.checkout("dev", in: path)
            try await gitService.merge("origin/dev", in: path)
            logger.info("Merged PR #\(prNumber) into dev")
        } catch {
            logger.error("Failed to merge PR #\(prNumber) into dev: \(error.localizedDescription)")
        }
    }

    /// Check if all tasks for a feature have passed. If so, create a PR from dev → staging.
    /// Returns the PR number or nil.
    func checkFeatureCompletionAndPromote(featureId: UUID, projectId: UUID, in path: String) async -> Int? {
        do {
            let (allPassed, feature) = try await dbQueue.read { db -> (Bool, Feature?) in
                let feature = try Feature.fetchOne(db, id: featureId)
                let tasks = try AgentTask
                    .filter(Column("featureId") == featureId)
                    .fetchAll(db)

                // All tasks must be in a terminal success state
                let allPassed = !tasks.isEmpty && tasks.allSatisfy { $0.status == .passed }
                return (allPassed, feature)
            }

            guard allPassed, let feature else { return nil }
            // Don't create duplicate PRs
            guard feature.integrationPrNumber == nil else { return feature.integrationPrNumber }

            // Push dev branch
            try await gitHubService.push(branch: "dev", in: path)

            // Create PR from dev → staging
            let pr = try await gitHubService.createPR(
                title: "Integrate: \(feature.name)",
                body: "All tasks for feature \"\(feature.name)\" have passed review.\n\nAutomated promotion from dev → staging by CreedFlow.",
                base: "staging",
                head: "dev",
                in: path
            )

            // Store PR number on feature
            try await dbQueue.write { db in
                var updated = feature
                updated.integrationPrNumber = pr.number
                updated.updatedAt = Date()
                try updated.update(db)
            }

            logger.info("Created integration PR #\(pr.number) dev → staging for feature \(feature.name)")
            return pr.number
        } catch {
            logger.error("Feature completion check failed for \(featureId): \(error.localizedDescription)")
            return nil
        }
    }

    /// After staging deploy succeeds, create PR from staging → main.
    /// Returns the PR number or nil.
    func promoteStagingToMain(projectId: UUID, version: String, in path: String) async -> Int? {
        do {
            // Push staging
            try await gitHubService.push(branch: "staging", in: path)

            // Create PR from staging → main
            let pr = try await gitHubService.createPR(
                title: "Release: \(version)",
                body: "Staging deployment verified. Promoting staging → main.\n\nVersion: \(version)\n\nAutomated by CreedFlow.",
                base: "main",
                head: "staging",
                in: path
            )

            // Store PR number on project
            try await dbQueue.write { db in
                guard var project = try Project.fetchOne(db, id: projectId) else { return }
                project.stagingPrNumber = pr.number
                project.updatedAt = Date()
                try project.update(db)
            }

            logger.info("Created release PR #\(pr.number) staging → main for version \(version)")
            return pr.number
        } catch {
            logger.error("Staging → main promotion failed for project \(projectId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private func logError(taskId: UUID, agent: AgentTask.AgentType, message: String) async throws {
        try await dbQueue.write { db in
            let log = AgentLog(
                taskId: taskId,
                agentType: agent,
                level: .error,
                message: message
            )
            try log.insert(db)
        }
    }
}
