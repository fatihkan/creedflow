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
        claudePath: String? = nil
    ) {
        self.dbQueue = dbQueue
        self.taskQueue = TaskQueue(dbQueue: dbQueue)
        self.scheduler = AgentScheduler(maxConcurrency: maxConcurrency)

        // Resolve claude path: explicit > AppStorage > PATH lookup > common locations
        let resolvedPath = claudePath
            ?? UserDefaults.standard.string(forKey: "claudePath").flatMap({ $0.isEmpty ? nil : $0 })
            ?? Self.findClaudeCLI()
        self.processManager = ClaudeProcessManager(claudePath: resolvedPath)

        self.gitService = GitService()
        self.gitHubService = GitHubService()
        self.projectDirService = ProjectDirectoryService()
        self.retryPolicy = .default
    }

    /// Try to find the claude CLI binary
    private static func findClaudeCLI() -> String {
        let candidates = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return candidates[0] // fallback
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

                // Resolve working directory from project
                let workingDir = try await self.resolveWorkingDirectory(for: task)

                let result = try await runner.execute(task: task, agent: agent, workingDirectory: workingDir)

                // Post-completion pipeline
                await self.handleTaskCompletion(task: task, result: result)
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

    /// Resolve the working directory for a task from its project
    private func resolveWorkingDirectory(for task: AgentTask) async throws -> String {
        let project = try await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        guard let project, !project.directoryPath.isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return project.directoryPath
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

    /// Handle post-completion pipeline
    private func handleTaskCompletion(task: AgentTask, result: AgentResult) async {
        switch task.agentType {
        case .analyzer:
            // After analyzer: parse JSON → create features + tasks in DB
            await handleAnalyzerCompletion(task: task, result: result)
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

    /// Parse analyzer JSON output and create features + tasks in DB
    private func handleAnalyzerCompletion(task: AgentTask, result: AgentResult) async {
        guard let output = result.output, let data = output.data(using: .utf8) else {
            try? await logError(taskId: task.id, agent: .analyzer, message: "Analyzer returned no output")
            return
        }

        // Parse the structured JSON output
        struct AnalyzerOutput: Decodable {
            let projectName: String?
            let techStack: String?
            let features: [FeatureOutput]

            struct FeatureOutput: Decodable {
                let name: String
                let description: String
                let priority: Int
                let tasks: [TaskOutput]
            }

            struct TaskOutput: Decodable {
                let title: String
                let description: String
                let agentType: String
                let priority: Int
                let dependsOn: [String]?
            }
        }

        do {
            let parsed = try JSONDecoder().decode(AnalyzerOutput.self, from: data)

            // Update project tech stack if provided
            if let techStack = parsed.techStack {
                try await dbQueue.write { db in
                    var project = try Project.fetchOne(db, id: task.projectId)!
                    project.techStack = techStack
                    project.status = .inProgress
                    project.updatedAt = Date()
                    try project.update(db)
                }
            }

            // Create features and tasks
            // First pass: create all features and tasks, collect title → id mapping
            var titleToTaskId: [String: UUID] = [:]

            try await dbQueue.write { db in
                for featureOutput in parsed.features {
                    // Create feature
                    var feature = Feature(
                        projectId: task.projectId,
                        name: featureOutput.name,
                        description: featureOutput.description,
                        priority: featureOutput.priority
                    )
                    try feature.insert(db)

                    // Create tasks for this feature
                    for taskOutput in featureOutput.tasks {
                        let agentType: AgentTask.AgentType
                        switch taskOutput.agentType.lowercased() {
                        case "coder": agentType = .coder
                        case "devops": agentType = .devops
                        case "tester": agentType = .tester
                        case "reviewer": agentType = .reviewer
                        default: agentType = .coder
                        }

                        var newTask = AgentTask(
                            projectId: task.projectId,
                            featureId: feature.id,
                            agentType: agentType,
                            title: taskOutput.title,
                            description: taskOutput.description,
                            priority: taskOutput.priority
                        )
                        try newTask.insert(db)
                        titleToTaskId[taskOutput.title] = newTask.id
                    }
                }

                // Second pass: create dependency edges
                for featureOutput in parsed.features {
                    for taskOutput in featureOutput.tasks {
                        guard let deps = taskOutput.dependsOn, !deps.isEmpty else { continue }
                        guard let taskId = titleToTaskId[taskOutput.title] else { continue }

                        for depTitle in deps {
                            if let depId = titleToTaskId[depTitle] {
                                let dep = TaskDependency(taskId: taskId, dependsOnTaskId: depId)
                                try dep.insert(db)
                            }
                        }
                    }
                }
            }

            let totalTasks = titleToTaskId.count
            try? await logInfo(taskId: task.id, agent: .analyzer,
                             message: "Created \(parsed.features.count) features and \(totalTasks) tasks")

        } catch {
            try? await logError(taskId: task.id, agent: .analyzer,
                              message: "Failed to parse analyzer output: \(error.localizedDescription)")
        }
    }

    private func logError(taskId: UUID, agent: AgentTask.AgentType, message: String) async throws {
        try await dbQueue.write { db in
            var log = AgentLog(taskId: taskId, agentType: agent, level: .error, message: message)
            try log.insert(db)
        }
    }

    private func logInfo(taskId: UUID, agent: AgentTask.AgentType, message: String) async throws {
        try await dbQueue.write { db in
            var log = AgentLog(taskId: taskId, agentType: agent, level: .info, message: message)
            try log.insert(db)
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
