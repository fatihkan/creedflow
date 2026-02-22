import Foundation
import GRDB

/// Central coordination loop that polls for ready tasks and dispatches them to agents.
@Observable
final class Orchestrator {
    private let dbQueue: DatabaseQueue
    private let taskQueue: TaskQueue
    private let scheduler: AgentScheduler
    private let processManager: ClaudeProcessManager
    private let gitService: GitService
    private let gitHubService: GitHubService
    private let projectDirService: ProjectDirectoryService
    private let retryPolicy: RetryPolicy

    private(set) var isRunning = false
    private(set) var activeRunners: [UUID: ClaudeAgentRunner] = [:]
    private var pollingTask: Task<Void, Never>?

    init(
        dbQueue: DatabaseQueue,
        maxConcurrency: Int = 3,
        claudePath: String = "/usr/local/bin/claude"
    ) {
        self.dbQueue = dbQueue
        self.taskQueue = TaskQueue(dbQueue: dbQueue)
        self.scheduler = AgentScheduler(maxConcurrency: maxConcurrency)
        self.processManager = ClaudeProcessManager(claudePath: claudePath)
        self.gitService = GitService()
        self.gitHubService = GitHubService()
        self.projectDirService = ProjectDirectoryService()
        self.retryPolicy = .default
    }

    /// Start the orchestration loop
    func start() async {
        guard !isRunning else { return }
        isRunning = true

        // Recover orphaned tasks from previous crash
        try? await taskQueue.recoverOrphanedTasks()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollAndDispatch()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Stop the orchestration loop and cancel all active agents
    func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
        await processManager.cancelAll()
        activeRunners.removeAll()
    }

    /// Get a runner for a specific task (for UI display of live output)
    func runner(for taskId: UUID) -> ClaudeAgentRunner? {
        activeRunners[taskId]
    }

    // MARK: - Private

    private func pollAndDispatch() async {
        // Try to dequeue a task
        guard let task = try? await taskQueue.dequeue() else { return }

        // Check if scheduler has a slot
        let acquired = await scheduler.acquire(task: task)
        guard acquired else {
            // Can't schedule now (e.g., coder conflict), requeue
            try? await taskQueue.requeue(task)
            return
        }

        // Create a runner for this task
        let runner = ClaudeAgentRunner(processManager: processManager, dbQueue: dbQueue)
        activeRunners[task.id] = runner

        // Dispatch in a Swift Task
        Task { [weak self] in
            defer {
                Task { [weak self] in
                    await self?.scheduler.release(task: task)
                    self?.activeRunners.removeValue(forKey: task.id)
                }
            }

            let agent = self?.resolveAgent(for: task.agentType)
            guard let agent, let self else { return }

            do {
                // For coder tasks, set up git branch first
                if task.agentType == .coder {
                    try await self.setupCoderBranch(task: task)
                }

                let _ = try await runner.execute(task: task, agent: agent)

                // Post-completion pipeline
                await self.handleTaskCompletion(task: task)
            } catch {
                // Handle retry
                if self.retryPolicy.shouldRetry(task: task, error: error) {
                    let backoff = self.retryPolicy.backoffInterval(for: task.retryCount)
                    try? await Task.sleep(for: .seconds(backoff))
                    try? await self.taskQueue.requeue(task)
                } else {
                    try? await self.taskQueue.fail(task, error: error.localizedDescription)
                }
            }
        }
    }

    private func resolveAgent(for type: AgentTask.AgentType) -> any AgentProtocol {
        switch type {
        case .analyzer: return AnalyzerAgent()
        case .coder: return CoderAgent()
        case .reviewer: return ReviewerAgent()
        case .tester: return TesterAgent()
        case .devops: return DevOpsAgent()
        case .monitor: return MonitorAgent()
        }
    }

    /// Set up a git branch for coder tasks
    private func setupCoderBranch(task: AgentTask) async throws {
        let project = try await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        guard let project else { return }

        let branchName = "feature/\(task.id.uuidString.prefix(8))-\(sanitize(task.title))"
        try await gitService.createBranch(branchName, in: project.directoryPath)

        // Update task with branch name
        try await dbQueue.write { db in
            var updated = task
            updated.branchName = branchName
            updated.updatedAt = Date()
            try updated.update(db)
        }
    }

    /// Handle post-completion pipeline (coder → commit → reviewer)
    private func handleTaskCompletion(task: AgentTask) async {
        switch task.agentType {
        case .coder:
            // After coder: commit changes, push, create PR, queue reviewer
            await handleCoderCompletion(task: task)
        case .reviewer:
            // After reviewer: parse result, update review status
            break
        default:
            break
        }
    }

    private func handleCoderCompletion(task: AgentTask) async {
        guard let branchName = task.branchName else { return }

        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        guard let project else { return }

        do {
            // Stage, commit, push
            try await gitService.addAll(in: project.directoryPath)
            try await gitService.commit(
                message: "feat: \(task.title)\n\nTask: \(task.id)",
                in: project.directoryPath
            )
            try await gitHubService.push(branch: branchName, in: project.directoryPath)

            // Create PR
            let pr = try await gitHubService.createPR(
                title: task.title,
                body: "Automated by CodeForge\n\nTask: \(task.id)\n\n\(task.description)",
                head: branchName,
                in: project.directoryPath
            )

            // Update task with PR number
            try await dbQueue.write { db in
                var updated = task
                updated.prNumber = pr.number
                updated.updatedAt = Date()
                try updated.update(db)
            }

            // Queue reviewer task
            try await dbQueue.write { db in
                var reviewTask = AgentTask(
                    projectId: task.projectId,
                    featureId: task.featureId,
                    agentType: .reviewer,
                    title: "Review: \(task.title)",
                    description: "Review the code changes in branch \(branchName) for task: \(task.title)",
                    priority: task.priority + 1,
                    branchName: branchName
                )
                try reviewTask.insert(db)

                // Add dependency: review depends on coder task
                let dep = TaskDependency(taskId: reviewTask.id, dependsOnTaskId: task.id)
                try dep.insert(db)
            }
        } catch {
            // Log git/PR errors but don't fail the task
            try? await dbQueue.write { db in
                var log = AgentLog(
                    taskId: task.id,
                    agentType: .coder,
                    level: .error,
                    message: "Post-completion error: \(error.localizedDescription)"
                )
                try log.insert(db)
            }
        }
    }

    private func sanitize(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(30)
            .description
    }
}
