import Foundation
import GRDB

/// Central coordination loop that polls for ready tasks and dispatches them to agents.
@Observable
final class Orchestrator {
    private let dbQueue: DatabaseQueue
    private let taskQueue: TaskQueue
    private let scheduler: AgentScheduler
    private let processManager: ClaudeProcessManager
    private let backendRouter: BackendRouter
    private let gitService: GitService
    private let gitHubService: GitHubService
    private let projectDirService: ProjectDirectoryService
    private let retryPolicy: RetryPolicy
    private let telegramService: TelegramBotService?
    private let localDeployService: LocalDeploymentService

    private(set) var isRunning = false
    private(set) var activeRunners: [UUID: MultiBackendRunner] = [:]
    private var pollingTask: Task<Void, Never>?

    init(
        dbQueue: DatabaseQueue,
        maxConcurrency: Int = 3,
        claudePath: String? = nil,
        telegramService: TelegramBotService? = nil
    ) {
        self.dbQueue = dbQueue
        self.taskQueue = TaskQueue(dbQueue: dbQueue)
        self.scheduler = AgentScheduler(maxConcurrency: maxConcurrency)

        // Resolve claude path: explicit > AppStorage > PATH lookup > common locations
        let resolvedPath = claudePath
            ?? UserDefaults.standard.string(forKey: "claudePath").flatMap({ $0.isEmpty ? nil : $0 })
            ?? Self.findClaudeCLI()
        self.processManager = ClaudeProcessManager(claudePath: resolvedPath)

        // Set up backend router with all available backends
        let router = BackendRouter()
        self.backendRouter = router

        self.gitService = GitService()
        self.gitHubService = GitHubService()
        self.projectDirService = ProjectDirectoryService()
        self.retryPolicy = .default
        self.telegramService = telegramService
        self.localDeployService = LocalDeploymentService(dbQueue: dbQueue)

        // Register backends (done after init to avoid capturing self before init completes)
        let pm = self.processManager
        Task {
            await router.register(ClaudeBackend(processManager: pm))
            await router.register(CodexBackend())
            await router.register(GeminiBackend())
        }
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
        // Cancel all backends
        for backend in await backendRouter.allBackends {
            await backend.cancelAll()
        }
        activeRunners.removeAll()
    }

    /// Get a runner for a specific task (for UI display of live output)
    func runner(for taskId: UUID) -> MultiBackendRunner? {
        activeRunners[taskId]
    }

    // MARK: - Private

    private func pollAndDispatch() async {
        // Try to dequeue a task
        guard let task = try? await taskQueue.dequeue() else { return }

        // Check if scheduler has a slot (non-blocking)
        let acquired = await scheduler.tryAcquire(task: task)
        guard acquired else {
            // Can't schedule now (no slot or coder conflict), defer without incrementing retryCount
            try? await taskQueue.deferTask(task)
            return
        }

        // Select backend and create a runner for this task
        let agent = resolveAgent(for: task.agentType)
        let backend = await backendRouter.selectBackend(agent: agent, task: task)
        let runner = MultiBackendRunner(backend: backend, dbQueue: dbQueue)
        activeRunners[task.id] = runner

        // Dispatch in a Swift Task
        Task { [weak self, agent] in
            defer {
                Task { [weak self] in
                    await self?.scheduler.release(task: task)
                    self?.activeRunners.removeValue(forKey: task.id)
                }
            }

            guard let self else { return }

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

                // Check if project is fully done and backfill prompt usage outcomes
                await self.checkProjectCompletion(projectId: task.projectId)

                // Telegram notification: task completed
                await self.sendTelegramNotification(for: task) { telegram, project in
                    await telegram.notifyTaskCompleted(task: task, project: project)
                }
            } catch {
                // Handle retry
                if self.retryPolicy.shouldRetry(task: task, error: error) {
                    let backoff = self.retryPolicy.backoffInterval(for: task.retryCount)
                    try? await Task.sleep(for: .seconds(backoff))
                    try? await self.taskQueue.requeue(task)
                } else {
                    try? await self.taskQueue.fail(task, error: error.localizedDescription)

                    // Telegram notification: task failed (no more retries)
                    await self.sendTelegramNotification(for: task) { telegram, project in
                        await telegram.notifyTaskFailed(task: task, project: project)
                    }
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
        case .contentWriter: return ContentWriterAgent()
        case .designer: return DesignerAgent()
        case .imageGenerator: return ImageGeneratorAgent()
        case .videoEditor: return VideoEditorAgent()
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
            await handleReviewerCompletion(task: task, result: result)
        case .devops:
            await handleDevOpsCompletion(task: task, result: result)
        default:
            break
        }
    }

    /// Extract JSON from text that might contain markdown code blocks or extra text
    private func extractJSON(from text: String) -> Data? {
        // Try direct parse first
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        // Try extracting from ```json ... ``` block
        if let start = text.range(of: "```json"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            let json = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return json.data(using: .utf8)
        }
        // Try extracting from ``` ... ``` block
        if let start = text.range(of: "```"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            let json = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return json.data(using: .utf8)
        }
        // Try finding first { to last }
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}") {
            let json = String(text[firstBrace...lastBrace])
            return json.data(using: .utf8)
        }
        return nil
    }

    /// Parse analyzer JSON output and create features + tasks in DB
    private func handleAnalyzerCompletion(task: AgentTask, result: AgentResult) async {
        guard let output = result.output else {
            try? await logError(taskId: task.id, agent: .analyzer, message: "Analyzer returned no output")
            return
        }

        guard let data = extractJSON(from: output) else {
            try? await logError(taskId: task.id, agent: .analyzer, message: "Could not extract JSON from analyzer output: \(output.prefix(200))")
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

            // Build title → UUID mapping (pre-generate to avoid duplicates)
            var titleToTaskId: [String: UUID] = [:]
            for featureOutput in parsed.features {
                for taskOutput in featureOutput.tasks {
                    // Use first occurrence to handle duplicate titles (#41)
                    if titleToTaskId[taskOutput.title] == nil {
                        titleToTaskId[taskOutput.title] = UUID()
                    }
                }
            }

            // Validate dependency graph for cycles (#35)
            var depGraph = DependencyGraph()
            for (_, taskId) in titleToTaskId {
                depGraph.addNode(taskId)
            }
            for featureOutput in parsed.features {
                for taskOutput in featureOutput.tasks {
                    guard let deps = taskOutput.dependsOn, !deps.isEmpty else { continue }
                    guard let taskId = titleToTaskId[taskOutput.title] else { continue }
                    for depTitle in deps {
                        if let depId = titleToTaskId[depTitle] {
                            depGraph.addDependency(task: taskId, dependsOn: depId)
                        }
                    }
                }
            }
            // Cycle detection — log warning but don't block task creation
            do {
                _ = try depGraph.topologicalSort()
            } catch {
                try? await logError(taskId: task.id, agent: .analyzer,
                                   message: "Dependency cycle detected: \(error.localizedDescription)")
            }

            // Create features and tasks in DB
            try await dbQueue.write { db in
                for featureOutput in parsed.features {
                    let feature = Feature(
                        projectId: task.projectId,
                        name: featureOutput.name,
                        description: featureOutput.description,
                        priority: featureOutput.priority
                    )
                    try feature.insert(db)

                    for taskOutput in featureOutput.tasks {
                        guard let pregenId = titleToTaskId[taskOutput.title] else { continue }
                        let agentType: AgentTask.AgentType
                        switch taskOutput.agentType.lowercased() {
                        case "coder": agentType = .coder
                        case "devops": agentType = .devops
                        case "tester": agentType = .tester
                        case "reviewer": agentType = .reviewer
                        case "contentwriter": agentType = .contentWriter
                        case "designer": agentType = .designer
                        case "imagegenerator": agentType = .imageGenerator
                        case "videoeditor": agentType = .videoEditor
                        default: agentType = .coder
                        }

                        let newTask = AgentTask(
                            id: pregenId,
                            projectId: task.projectId,
                            featureId: feature.id,
                            agentType: agentType,
                            title: taskOutput.title,
                            description: taskOutput.description,
                            priority: taskOutput.priority
                        )
                        try newTask.insert(db)
                    }
                }

                // Create dependency edges
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
            let log = AgentLog(taskId: taskId, agentType: agent, level: .error, message: message)
            try log.insert(db)
        }
    }

    private func logInfo(taskId: UUID, agent: AgentTask.AgentType, message: String) async throws {
        try await dbQueue.write { db in
            let log = AgentLog(taskId: taskId, agentType: agent, level: .info, message: message)
            try log.insert(db)
        }
    }

    /// Parse reviewer JSON output and create a Review record
    private func handleReviewerCompletion(task: AgentTask, result: AgentResult) async {
        guard let output = result.output else {
            try? await logError(taskId: task.id, agent: .reviewer, message: "Reviewer returned no output")
            return
        }

        guard let data = extractJSON(from: output) else {
            try? await logError(taskId: task.id, agent: .reviewer, message: "Could not extract JSON from reviewer output: \(output.prefix(200))")
            return
        }

        struct ReviewerOutput: Decodable {
            let score: Double
            let verdict: String
            let summary: String
            let issues: FlexibleStringField?
            let suggestions: FlexibleStringField?
            let securityNotes: FlexibleStringField?
        }

        /// Decodes either a String or [String] into a single joined String
        struct FlexibleStringField: Decodable {
            let value: String

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let str = try? container.decode(String.self) {
                    value = str
                } else if let arr = try? container.decode([String].self) {
                    value = arr.joined(separator: "\n")
                } else {
                    value = ""
                }
            }
        }

        do {
            let parsed = try JSONDecoder().decode(ReviewerOutput.self, from: data)

            let verdict: Review.Verdict
            switch parsed.verdict.lowercased() {
            case "pass": verdict = .pass
            case "needs_revision", "needsrevision", "needs-revision": verdict = .needsRevision
            default: verdict = .fail
            }

            // Insert review record
            try await dbQueue.write { db in
                let review = Review(
                    taskId: task.id,
                    score: parsed.score,
                    verdict: verdict,
                    summary: parsed.summary,
                    issues: parsed.issues?.value,
                    suggestions: parsed.suggestions?.value,
                    securityNotes: parsed.securityNotes?.value,
                    sessionId: result.sessionId,
                    costUSD: result.costUSD
                )
                try review.insert(db)

                // Backfill review score on prompt usage records for this project
                try PromptUsage
                    .filter(Column("projectId") == task.projectId)
                    .filter(Column("reviewScore") == nil)
                    .updateAll(db, Column("reviewScore").set(to: parsed.score))
            }

            // Find the original coder task (the one this review task depends on)
            // and update its status based on the verdict
            if verdict != .pass {
                let coderTaskStatus: AgentTask.Status = verdict == .needsRevision ? .needsRevision : .failed
                try await dbQueue.write { db in
                    // Find dependency: this reviewer task depends on a coder task
                    let deps = try TaskDependency
                        .filter(Column("taskId") == task.id)
                        .fetchAll(db)
                    for dep in deps {
                        var coderTask = try AgentTask.fetchOne(db, id: dep.dependsOnTaskId)
                        if coderTask?.agentType == .coder {
                            coderTask?.status = coderTaskStatus
                            coderTask?.updatedAt = Date()
                            try coderTask?.update(db)
                        }
                    }
                }
            }

            try? await logInfo(taskId: task.id, agent: .reviewer,
                             message: "Review completed: score=\(parsed.score), verdict=\(verdict.rawValue)")

            // Telegram notification: review completed
            let reviewForNotification = Review(
                taskId: task.id, score: parsed.score, verdict: verdict,
                summary: parsed.summary, issues: parsed.issues?.value,
                suggestions: parsed.suggestions?.value, securityNotes: parsed.securityNotes?.value
            )
            await sendTelegramNotification(for: task) { telegram, project in
                await telegram.notifyReviewCompleted(review: reviewForNotification, task: task, project: project)
            }

        } catch {
            try? await logError(taskId: task.id, agent: .reviewer,
                              message: "Failed to parse reviewer output: \(error.localizedDescription)")
        }
    }

    private func handleCoderCompletion(task: AgentTask) async {
        guard let branchName = task.branchName else { return }

        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        guard let project else { return }

        do {
            // Stage all changes first
            try await gitService.addAll(in: project.directoryPath)

            // Check for empty diff before committing (#34)
            let status = try await gitService.status(in: project.directoryPath)
            guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                try? await logInfo(taskId: task.id, agent: .coder,
                                  message: "No changes to commit — skipping PR and review")
                return
            }

            try await gitService.commit(
                message: "feat: \(task.title)\n\nTask: \(task.id)",
                in: project.directoryPath
            )
            try await gitHubService.push(branch: branchName, in: project.directoryPath)

            // Create PR
            let pr = try await gitHubService.createPR(
                title: task.title,
                body: "Automated by CreedFlow\n\nTask: \(task.id)\n\n\(task.description)",
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
                let reviewTask = AgentTask(
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
                let log = AgentLog(
                    taskId: task.id,
                    agentType: .coder,
                    level: .error,
                    message: "Post-completion error: \(error.localizedDescription)"
                )
                try log.insert(db)
            }
        }
    }

    /// Update deployment status after devops task completes, then run actual deployment (#30)
    private func handleDevOpsCompletion(task: AgentTask, result: AgentResult) async {
        do {
            // Find the pending deployment for this project
            let deployment = try await dbQueue.read { db in
                try Deployment
                    .filter(Column("projectId") == task.projectId)
                    .filter(Column("status") == Deployment.Status.pending.rawValue)
                    .order(Column("createdAt").desc)
                    .fetchOne(db)
            }

            guard var deployment else {
                try? await logInfo(taskId: task.id, agent: .devops,
                                  message: "No pending deployment found — skipping local deploy")
                return
            }

            // If devops agent task failed, mark deployment as failed
            guard task.status == .passed else {
                deployment.status = .failed
                deployment.completedAt = Date()
                deployment.logs = task.errorMessage ?? result.output
                let failedDeployment = deployment
                try await dbQueue.write { db in
                    var d = failedDeployment
                    try d.update(db)
                }
                return
            }

            // Resolve project for directory path
            let project = try await dbQueue.read { db in
                try Project.fetchOne(db, id: task.projectId)
            }
            guard let project else { return }

            let port = deployment.port ?? (deployment.environment == .production ? 3000 : 3001)
            deployment.port = port

            // Run actual local deployment
            _ = try await localDeployService.deploy(
                project: project,
                deployment: deployment,
                port: port
            )

            try? await logInfo(taskId: task.id, agent: .devops,
                             message: "Local deployment completed on port \(port)")

        } catch {
            try? await logError(taskId: task.id, agent: .devops,
                              message: "Failed to deploy: \(error.localizedDescription)")
        }
    }

    /// Backfill PromptUsage outcome when a project reaches a terminal status.
    private func backfillPromptUsageOutcome(projectId: UUID, outcome: PromptUsage.Outcome) async {
        _ = try? await dbQueue.write { db in
            try PromptUsage
                .filter(Column("projectId") == projectId)
                .filter(Column("outcome") == nil)
                .updateAll(db, Column("outcome").set(to: outcome.rawValue))
        }
    }

    /// Check if all tasks for a project are done and update project + prompt usage accordingly.
    private func checkProjectCompletion(projectId: UUID) async {
        do {
            let (allDone, anyFailed) = try await dbQueue.read { db -> (Bool, Bool) in
                let tasks = try AgentTask.filter(Column("projectId") == projectId).fetchAll(db)
                let pending = tasks.contains { $0.status == .queued || $0.status == .inProgress }
                let failed = tasks.contains { $0.status == .failed }
                return (!pending, failed)
            }
            guard allDone else { return }

            let outcome: PromptUsage.Outcome = anyFailed ? .failed : .completed
            await backfillPromptUsageOutcome(projectId: projectId, outcome: outcome)
        } catch {
            // Non-critical — log and continue
        }
    }

    private func sanitize(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(30)
            .description
    }

    // MARK: - Telegram Notifications

    private func sendTelegramNotification(
        for task: AgentTask,
        action: @escaping (TelegramBotService, Project) async -> Void
    ) async {
        guard let telegram = telegramService else { return }
        guard let project = try? await dbQueue.read({ db in
            try Project.fetchOne(db, id: task.projectId)
        }) else { return }
        // Only send if project has a telegram chat configured
        guard project.telegramChatId != nil else { return }
        await action(telegram, project)
    }
}
