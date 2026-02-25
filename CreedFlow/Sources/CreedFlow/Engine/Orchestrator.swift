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
    private let assetService: AssetStorageService
    private let thumbnailService: ThumbnailGeneratorService
    private let publishingService: ContentPublishingService

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
        self.assetService = AssetStorageService(dbQueue: dbQueue)
        self.thumbnailService = ThumbnailGeneratorService()
        self.publishingService = ContentPublishingService(dbQueue: dbQueue)

        // Register backends (done after init to avoid capturing self before init completes)
        // All three are registered; BackendRouter checks isEnabled + isAvailable before selection.
        let pm = self.processManager
        let claudeResolvedPath = resolvedPath
        Task {
            await router.register(ClaudeBackend(processManager: pm, claudePath: claudeResolvedPath))
            await router.register(CodexBackend())
            await router.register(GeminiBackend())
            await router.register(OllamaBackend())
            await router.register(LMStudioBackend())
            await router.register(LlamaCppBackend())
            await router.register(MLXBackend())
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

        // Start scheduled publication polling
        await publishingService.startScheduledPublishing()

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
        await publishingService.stopScheduledPublishing()
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
        guard let backend = await backendRouter.selectBackend(agent: agent, task: task) else {
            // No enabled/available backend — defer the task back to queue
            await scheduler.release(task: task)
            try? await taskQueue.deferTask(task)
            return
        }
        let runner = MultiBackendRunner(backend: backend, dbQueue: dbQueue)
        activeRunners[task.id] = runner

        // Record selected backend immediately so UI shows it during in_progress
        let selectedBackend = backend.backendType.rawValue
        try? await dbQueue.write { db in
            var t = task
            t.backend = selectedBackend
            t.updatedAt = Date()
            try t.update(db)
        }

        // [Feature 3] Build template values from project + task context
        let templateValues = await buildTemplateValues(for: task)

        // [Feature 1] Get prompt recommendation based on effectiveness metrics
        let recommender = PromptRecommender(dbQueue: dbQueue)
        let recommendation = recommender.recommend(for: task.agentType)

        // Dispatch in a Swift Task
        Task { [weak self, agent, templateValues, recommendation] in
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

                let result: AgentResult

                // [Feature 2] Chain execution path
                if let chainId = task.promptChainId {
                    let chainExecutor = ChainExecutor(dbQueue: self.dbQueue, backendRouter: self.backendRouter)
                    result = try await chainExecutor.execute(
                        chainId: chainId,
                        task: task,
                        agent: agent,
                        workingDirectory: workingDir,
                        templateValues: templateValues,
                        runner: runner
                    )
                } else {
                    // Normal path: apply recommendation + template variables
                    var promptOverride: String?
                    if let rec = recommendation {
                        let resolved = TemplateVariableResolver.resolve(template: rec.prompt.content, values: templateValues)
                        // Augment: prepend recommended prompt context to agent's default prompt
                        let agentPrompt = agent.buildPrompt(for: task)
                        promptOverride = resolved + "\n\n" + agentPrompt
                    }

                    result = try await runner.execute(
                        task: task,
                        agent: agent,
                        workingDirectory: workingDir,
                        promptOverride: promptOverride
                    )

                    // [Feature 1] Record prompt usage on dispatch
                    if let rec = recommendation {
                        recommender.recordUsage(
                            promptId: rec.prompt.id,
                            projectId: task.projectId,
                            taskId: task.id,
                            agentType: task.agentType
                        )
                    }
                }

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

    /// Build template variable values from project + task context.
    private func buildTemplateValues(for task: AgentTask) async -> [String: String] {
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        return TemplateVariableResolver.allValues(
            projectName: project?.name,
            techStack: project?.techStack,
            projectType: project?.projectType.rawValue,
            task: task
        )
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
        case .publisher: return PublisherAgent()
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
        case .designer:
            await handleCreativeCompletion(task: task, result: result, assetType: .design)
        case .imageGenerator:
            await handleCreativeCompletion(task: task, result: result, assetType: .image)
        case .videoEditor:
            await handleCreativeCompletion(task: task, result: result, assetType: .video)
        case .contentWriter:
            await handleContentWriterCompletion(task: task, result: result)
        case .publisher:
            await handlePublisherCompletion(task: task, result: result)
        default:
            break
        }
    }

    /// Strip ANSI escape codes from CLI output (color codes, cursor movement, etc.)
    private func stripANSI(_ text: String) -> String {
        // Matches sequences like \e[0m, \e[1;31m, \e[38;5;200m, etc.
        guard let regex = try? NSRegularExpression(pattern: "\\e\\[[0-9;]*[A-Za-z]") else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    /// Extract JSON from text that might contain markdown code blocks or extra text
    private func extractJSON(from rawText: String) -> Data? {
        let text = stripANSI(rawText)

        // Try direct parse first
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        // Try extracting from ```json ... ``` block (case-insensitive)
        if let start = text.range(of: "```json", options: .caseInsensitive),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            let json = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = json.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
        // Try extracting from ``` ... ``` block
        if let start = text.range(of: "```"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            let json = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = json.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
        // Try finding first { to last }
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}") {
            let json = String(text[firstBrace...lastBrace])
            if let data = json.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
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
                        case "publisher": agentType = .publisher
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

    // MARK: - Creative Agent Completion

    /// Handle completion for creative agents (designer, imageGenerator, videoEditor).
    /// Parses JSON output for asset references, saves them, and queues a review task.
    private func handleCreativeCompletion(task: AgentTask, result: AgentResult, assetType: GeneratedAsset.AssetType) async {
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        guard let project else { return }

        do {
            try await extractAndSaveAssets(output: result.output, task: task, project: project, defaultAssetType: assetType)
            await queueCreativeReview(for: task)
        } catch {
            try? await logError(taskId: task.id, agent: task.agentType,
                               message: "Creative completion error: \(error.localizedDescription)")
        }
    }

    /// Handle content writer completion — save output as document asset, queue publisher if channels exist.
    private func handleContentWriterCompletion(task: AgentTask, result: AgentResult) async {
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        guard let project else { return }

        do {
            try await extractAndSaveAssets(output: result.output, task: task, project: project, defaultAssetType: .document)

            // If publishing channels are configured, queue a publisher task
            let hasChannels = try await publishingService.enabledChannels().isEmpty == false
            if hasChannels {
                try await dbQueue.write { db in
                    let publishTask = AgentTask(
                        projectId: task.projectId,
                        featureId: task.featureId,
                        agentType: .publisher,
                        title: "Publish: \(task.title)",
                        description: "Select publishing channels and schedule publication for: \(task.title)",
                        priority: task.priority
                    )
                    try publishTask.insert(db)

                    let dep = TaskDependency(taskId: publishTask.id, dependsOnTaskId: task.id)
                    try dep.insert(db)
                }
            }
        } catch {
            try? await logError(taskId: task.id, agent: .contentWriter,
                               message: "Content writer completion error: \(error.localizedDescription)")
        }
    }

    /// Handle publisher agent completion — parse publication plan and create records.
    private func handlePublisherCompletion(task: AgentTask, result: AgentResult) async {
        guard let output = result.output else {
            try? await logError(taskId: task.id, agent: .publisher, message: "Publisher returned no output")
            return
        }

        guard let data = extractJSON(from: output) else {
            try? await logInfo(taskId: task.id, agent: .publisher, message: "No structured publication plan in output")
            return
        }

        struct PublisherOutput: Decodable {
            let publications: [PubItem]?

            struct PubItem: Decodable {
                let assetId: String?
                let channelId: String?
                let format: String?
                let title: String?
                let tags: [String]?
                let isDraft: Bool?
            }
        }

        do {
            let parsed = try JSONDecoder().decode(PublisherOutput.self, from: data)
            guard let items = parsed.publications, !items.isEmpty else {
                try? await logInfo(taskId: task.id, agent: .publisher, message: "No publications planned")
                return
            }

            for item in items {
                guard let assetIdStr = item.assetId, let assetId = UUID(uuidString: assetIdStr),
                      let channelIdStr = item.channelId, let channelId = UUID(uuidString: channelIdStr) else {
                    continue
                }

                let format = item.format.flatMap { Publication.ExportFormat(rawValue: $0) } ?? .markdown
                let options = PublishOptions(
                    title: item.title ?? task.title,
                    tags: item.tags ?? [],
                    isDraft: item.isDraft ?? false
                )

                _ = try? await publishingService.publish(
                    assetId: assetId,
                    channelId: channelId,
                    format: format,
                    options: options
                )
            }

            try? await logInfo(taskId: task.id, agent: .publisher,
                              message: "Processed \(items.count) publication(s)")
        } catch {
            try? await logError(taskId: task.id, agent: .publisher,
                               message: "Failed to parse publisher output: \(error.localizedDescription)")
        }
    }

    /// Parse agent output for asset references and save them via AssetStorageService.
    /// Supports JSON format: {"assets": [{"type": "...", "name": "...", "url"?: "...", "filePath"?: "...", "content"?: "..."}]}
    /// Falls back to saving raw output as a text file.
    private func extractAndSaveAssets(
        output: String?,
        task: AgentTask,
        project: Project,
        defaultAssetType: GeneratedAsset.AssetType
    ) async throws {
        guard let output, !output.isEmpty else {
            try? await logInfo(taskId: task.id, agent: task.agentType, message: "No output to save")
            return
        }

        // Try parsing structured JSON output
        if let data = extractJSON(from: output) {
            struct AssetOutput: Decodable {
                let assets: [AssetItem]?

                struct AssetItem: Decodable {
                    let type: String?
                    let name: String?
                    let url: String?
                    let filePath: String?
                    let content: String?
                }
            }

            if let parsed = try? JSONDecoder().decode(AssetOutput.self, from: data),
               let items = parsed.assets, !items.isEmpty {
                for (index, item) in items.enumerated() {
                    let assetType = item.type.flatMap { GeneratedAsset.AssetType(rawValue: $0) } ?? defaultAssetType
                    let name = item.name ?? "\(task.agentType.rawValue)-\(index + 1)"

                    if let urlStr = item.url, let url = URL(string: urlStr) {
                        _ = try await assetService.downloadAndSaveAsset(
                            url: url,
                            fileName: name,
                            project: project,
                            task: task,
                            assetType: assetType
                        )
                    } else if let path = item.filePath, FileManager.default.fileExists(atPath: path) {
                        _ = try await assetService.recordExistingAsset(
                            filePath: path,
                            project: project,
                            task: task,
                            assetType: assetType
                        )
                    } else if let content = item.content {
                        let ext = extensionForAssetType(assetType)
                        let fileName = name.contains(".") ? name : "\(name).\(ext)"
                        _ = try await assetService.saveTextAsset(
                            content: content,
                            fileName: fileName,
                            project: project,
                            task: task,
                            assetType: assetType
                        )
                    }
                }

                // Generate thumbnails for saved assets
                await generateThumbnailsForTask(taskId: task.id, projectName: project.name)

                try? await logInfo(taskId: task.id, agent: task.agentType,
                                  message: "Saved \(items.count) asset(s)")
                return
            }
        }

        // Fallback: save raw output as text file
        let ext = extensionForAssetType(defaultAssetType)
        let fileName = "\(task.agentType.rawValue)-\(task.id.uuidString.prefix(8)).\(ext)"
        _ = try await assetService.saveTextAsset(
            content: output,
            fileName: fileName,
            project: project,
            task: task,
            assetType: defaultAssetType
        )
        // Generate thumbnail for the fallback asset
        await generateThumbnailsForTask(taskId: task.id, projectName: project.name)

        try? await logInfo(taskId: task.id, agent: task.agentType,
                          message: "Saved raw output as \(fileName)")
    }

    /// Generate thumbnails for all assets belonging to a task.
    private func generateThumbnailsForTask(taskId: UUID, projectName: String) async {
        let assets = try? await dbQueue.read { db in
            try GeneratedAsset
                .filter(Column("taskId") == taskId)
                .filter(Column("thumbnailPath") == nil)
                .fetchAll(db)
        }
        guard let assets else { return }

        for asset in assets {
            if let thumbPath = await thumbnailService.generateThumbnail(for: asset, projectName: projectName) {
                try? await dbQueue.write { db in
                    var updated = asset
                    updated.thumbnailPath = thumbPath
                    updated.checksum = AssetVersioningService.computeChecksum(filePath: asset.filePath)
                    updated.updatedAt = Date()
                    try updated.update(db)
                }
            }
        }
    }

    /// Queue a reviewer task for creative output (same pattern as coder → reviewer).
    private func queueCreativeReview(for task: AgentTask) async {
        do {
            try await dbQueue.write { db in
                let reviewTask = AgentTask(
                    projectId: task.projectId,
                    featureId: task.featureId,
                    agentType: .reviewer,
                    title: "Review: \(task.title)",
                    description: "Review the creative output from \(task.agentType.rawValue) task: \(task.title)",
                    priority: task.priority + 1
                )
                try reviewTask.insert(db)

                // Add dependency: review depends on creative task
                let dep = TaskDependency(taskId: reviewTask.id, dependsOnTaskId: task.id)
                try dep.insert(db)

                // Link assets to review task
                try GeneratedAsset
                    .filter(Column("taskId") == task.id)
                    .updateAll(db,
                        Column("reviewTaskId").set(to: reviewTask.id),
                        Column("updatedAt").set(to: Date())
                    )
            }
        } catch {
            try? await logError(taskId: task.id, agent: task.agentType,
                               message: "Failed to queue creative review: \(error.localizedDescription)")
        }
    }

    private func extensionForAssetType(_ type: GeneratedAsset.AssetType) -> String {
        switch type {
        case .image: return "png"
        case .video: return "mp4"
        case .audio: return "mp3"
        case .design: return "json"
        case .document: return "md"
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
