import Foundation
import AppKit
import GRDB
import os.log

// MARK: - Analyzer Output Models

/// Data model produced by the Analyzer agent (database table, API endpoint, etc.)
struct AnalysisDataModel: Decodable {
    let name: String
    let type: String?
    let fields: [Field]?
    let relationships: [String]?

    struct Field: Decodable {
        let name: String
        let type: String
        let constraints: String?
    }
}

/// Mermaid diagram produced by the Analyzer agent.
struct AnalysisDiagram: Decodable {
    let title: String
    let type: String?
    let mermaid: String
}

/// Central coordination loop that polls for ready tasks and dispatches them to agents.
@Observable
final class Orchestrator {
    let logger = Logger(subsystem: "com.creedflow", category: "Orchestrator")
    let dbQueue: DatabaseQueue
    let taskQueue: TaskQueue
    private let scheduler: AgentScheduler
    private let processManager: ClaudeProcessManager
    let backendRouter: BackendRouter
    private let gitService: GitService
    private let gitHubService: GitHubService
    let projectDirService: ProjectDirectoryService
    private let retryPolicy: RetryPolicy
    private let telegramService: TelegramBotService?
    let localDeployService: LocalDeploymentService
    let assetService: AssetStorageService
    let thumbnailService: ThumbnailGeneratorService
    let publishingService: ContentPublishingService
    let contentExporter: ContentExporter
    let branchManager: GitBranchManager
    private let preferencesStore = AgentBackendPreferencesStore()
    let notificationService: NotificationService
    let backendHealthMonitor: BackendHealthMonitor
    let mcpHealthMonitor: MCPHealthMonitor
    let backendScoringService: BackendScoringService
    let budgetMonitorService: BudgetMonitorService

    /// Agent types that require at least one creative MCP service to be configured
    private static let creativeAgentTypes: Set<AgentTask.AgentType> = [
        .imageGenerator, .videoEditor, .designer
    ]

    private(set) var isRunning = false
    private(set) var activeRunners: [UUID: MultiBackendRunner] = [:]
    private let runnersLock = NSLock()
    private var pollingTask: Task<Void, Never>?

    init(
        dbQueue: DatabaseQueue,
        maxConcurrency: Int? = nil,
        claudePath: String? = nil,
        telegramService: TelegramBotService? = nil
    ) {
        self.dbQueue = dbQueue
        self.taskQueue = TaskQueue(dbQueue: dbQueue)

        // Read concurrency from Settings (UserDefaults) unless explicitly overridden
        let resolvedConcurrency = maxConcurrency
            ?? { let stored = UserDefaults.standard.integer(forKey: "maxConcurrency"); return stored > 0 ? stored : 3 }()
        self.scheduler = AgentScheduler(maxConcurrency: resolvedConcurrency)

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
        self.contentExporter = ContentExporter()
        self.branchManager = GitBranchManager(
            gitService: self.gitService,
            gitHubService: self.gitHubService,
            dbQueue: dbQueue
        )
        self.notificationService = NotificationService(dbQueue: dbQueue)
        self.backendHealthMonitor = BackendHealthMonitor(dbQueue: dbQueue, notificationService: self.notificationService)
        self.mcpHealthMonitor = MCPHealthMonitor(dbQueue: dbQueue, notificationService: self.notificationService)
        self.backendScoringService = BackendScoringService(dbQueue: dbQueue)
        self.budgetMonitorService = BudgetMonitorService(dbQueue: dbQueue, notificationService: self.notificationService)

        // Register backends (done after init to avoid capturing self before init completes)
        // All three are registered; BackendRouter checks isEnabled + isAvailable before selection.
        let pm = self.processManager
        let claudeResolvedPath = resolvedPath
        let scoring = self.backendScoringService
        Task {
            await router.register(ClaudeBackend(processManager: pm, claudePath: claudeResolvedPath))
            await router.register(CodexBackend())
            await router.register(GeminiBackend())
            await router.register(OpenCodeBackend())
            await router.register(OpenClawBackend())
            await router.register(OllamaBackend())
            await router.register(LMStudioBackend())
            await router.register(LlamaCppBackend())
            await router.register(MLXBackend())
            await router.setScoringService(scoring)
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

        // Start health monitors
        await backendHealthMonitor.start()
        await mcpHealthMonitor.start()

        // Start scoring and budget services
        await backendScoringService.start()
        await budgetMonitorService.start()

        // Prune old notifications
        await notificationService.pruneOld()

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
        await backendHealthMonitor.stop()
        await mcpHealthMonitor.stop()
        await backendScoringService.stop()
        await budgetMonitorService.stop()
        // Cancel all backends
        for backend in await backendRouter.allBackends {
            await backend.cancelAll()
        }
        runnersLock.lock()
        activeRunners.removeAll()
        runnersLock.unlock()
    }

    /// Get a runner for a specific task (for UI display of live output)
    func runner(for taskId: UUID) -> MultiBackendRunner? {
        runnersLock.lock()
        defer { runnersLock.unlock() }
        return activeRunners[taskId]
    }

    // MARK: - Private

    private func pollAndDispatch() async {
        // Fill all available scheduler slots in one cycle
        while true {
            // Try to dequeue a task
            let task: AgentTask
            do {
                guard let dequeued = try await taskQueue.dequeue() else { return }
                task = dequeued
            } catch {
                logger.error("Failed to dequeue task: \(error.localizedDescription)")
                return
            }

            // Check if scheduler has a slot (non-blocking)
            let acquired = await scheduler.tryAcquire(task: task)
            guard acquired else {
                // Can't schedule now (no slot or coder conflict), defer without incrementing retryCount
                do {
                    try await taskQueue.deferTask(task)
                } catch {
                    logger.error("Failed to defer task \(task.id) after scheduler full: \(error.localizedDescription)")
                }
                return  // All slots full — stop trying this cycle
            }

            // Select backend and create a runner for this task
            let agent = resolveAgent(for: task.agentType)

            // Validate creative agents have at least one MCP service configured
            if let mcpServers = agent.mcpServers, Self.creativeAgentTypes.contains(task.agentType) {
                let creativeMCPNames = mcpServers.filter { $0 != "creedflow" }
                let hasCreativeMCP = (try? await dbQueue.read { db in
                    try MCPServerConfig.fetchEnabled(names: creativeMCPNames, in: db).isEmpty == false
                }) ?? false
                if !hasCreativeMCP {
                    await scheduler.release(task: task)
                    let serviceList = creativeMCPNames.map { $0.capitalized }.joined(separator: ", ")
                    do {
                        try await taskQueue.fail(
                            task,
                            error: "No creative AI service configured. Go to Settings \u{2192} MCP Servers to add an API key for \(serviceList)."
                        )
                    } catch {
                        logger.error("Failed to mark task \(task.id) as failed (no creative MCP): \(error.localizedDescription)")
                    }
                    continue
                }
            }

            // Budget-aware dispatch: defer tasks when spending caps are exceeded
            let projectId = task.projectId
            if await budgetMonitorService.shouldPauseForBudget(projectId: projectId) {
                await scheduler.release(task: task)
                do {
                    try await taskQueue.deferTask(task)
                    logger.info("Task \(task.id) deferred — budget exceeded for project \(projectId)")
                } catch {
                    logger.error("Failed to defer task \(task.id) (budget exceeded): \(error.localizedDescription)")
                }
                continue
            }

            let effectivePrefs = preferencesStore.preferences(for: task.agentType)
            guard let backend = await backendRouter.selectBackend(preferences: effectivePrefs, task: task) else {
                // No enabled/available backend — defer the task back to queue
                await scheduler.release(task: task)
                do {
                    try await taskQueue.deferTask(task)
                } catch {
                    logger.error("Failed to defer task \(task.id) (no backend available): \(error.localizedDescription)")
                }
                continue  // No backend for THIS task, but others might have one
            }

            // Health-aware dispatch: skip unhealthy backends, defer task instead
            let healthStatus = await backendHealthMonitor.status(for: backend.backendType)
            if healthStatus == .unhealthy {
                await scheduler.release(task: task)
                do {
                    try await taskQueue.deferTask(task)
                } catch {
                    logger.error("Failed to defer task \(task.id) (unhealthy backend \(backend.backendType.rawValue)): \(error.localizedDescription)")
                }
                continue
            }
            let runner = MultiBackendRunner(backend: backend, dbQueue: dbQueue)
            runnersLock.lock()
            activeRunners[task.id] = runner
            runnersLock.unlock()

            // Record selected backend immediately so UI shows it during in_progress
            let selectedBackend = backend.backendType.rawValue
            do {
                try await dbQueue.write { db in
                    var t = task
                    t.backend = selectedBackend
                    t.updatedAt = Date()
                    try t.update(db)
                }
            } catch {
                logger.error("Failed to write backend selection for task \(task.id): \(error.localizedDescription)")
            }

            // [Feature 3] Build template values from project + task context
            let templateValues = await buildTemplateValues(for: task)

            // [Feature 1] Get prompt recommendation based on effectiveness metrics
            let recommender = PromptRecommender(dbQueue: dbQueue)
            let recommendation = recommender.recommend(for: task.agentType)

            // Dispatch in a Swift Task (fire-and-forget — loop continues immediately)
            Task { [weak self, agent, templateValues, recommendation] in
                defer {
                    Task { [weak self] in
                        await self?.scheduler.release(task: task)
                        self?.runnersLock.lock()
                        self?.activeRunners.removeValue(forKey: task.id)
                        self?.runnersLock.unlock()
                    }
                }

                guard let self else { return }

                do {
                    // For coder tasks, set up git branch first (best-effort)
                    if task.agentType == .coder {
                        await self.setupCoderBranch(task: task)
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

                        // Inject skill persona into prompt (from AgentPersona table, Prompt table fallback, or raw string)
                        if let personaName = task.skillPersona, !personaName.isEmpty {
                            // 1. Try AgentPersona table (structured personas)
                            let agentPersona = try? await self.dbQueue.read { db in
                                try AgentPersona.byName(personaName).fetchOne(db)
                            }

                            let skillContent: String
                            if let agentPersona = agentPersona {
                                skillContent = agentPersona.systemPrompt
                            } else {
                                // 2. Fallback: Prompt table lookup (backward compat)
                                let skillPrompt = try? await self.dbQueue.read { db in
                                    try Prompt
                                        .filter(Column("category") == "skill")
                                        .filter(Column("content").like("%\(String(personaName.prefix(50)))%"))
                                        .fetchOne(db)
                                }

                                if let skillPrompt = skillPrompt {
                                    skillContent = skillPrompt.content

                                    // Record PromptUsage for skill tracking
                                    try? await self.dbQueue.write { db in
                                        let usage = PromptUsage(
                                            promptId: skillPrompt.id,
                                            projectId: task.projectId,
                                            taskId: task.id,
                                            agentType: task.agentType.rawValue
                                        )
                                        try usage.insert(db)
                                    }
                                } else {
                                    // 3. Fallback: use raw string as-is
                                    skillContent = personaName
                                }
                            }

                            let personaPrefix = "<skill_persona>\nYou are: \(skillContent)\nApply this expertise throughout the task.\n</skill_persona>\n\n"
                            let base = promptOverride ?? agent.buildPrompt(for: task)
                            promptOverride = personaPrefix + base
                        }

                        // Inject revision memory for retry tasks
                        if task.retryCount > 0 || task.revisionPrompt != nil {
                            if let memory = await self.buildRevisionMemory(for: task) {
                                let base = promptOverride ?? agent.buildPrompt(for: task)
                                promptOverride = memory + base
                            }
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

                    // In-app notification: task completed
                    await self.notificationService.emit(
                        category: .task,
                        severity: .success,
                        title: "Task Completed",
                        message: task.title
                    )

                    // Telegram notification: task completed
                    await self.sendTelegramNotification(for: task) { telegram, project in
                        await telegram.notifyTaskCompleted(task: task, project: project)
                    }
                } catch {
                    // Rate-limit path: longer backoff + notification
                    if self.retryPolicy.isRateLimited(error: error) {
                        let backoff = self.retryPolicy.rateLimitBackoff(retryCount: task.retryCount)
                        await self.notificationService.emit(
                            category: .rateLimit,
                            severity: .warning,
                            title: "Rate Limited",
                            message: "\(task.title) — retrying in \(Int(backoff))s"
                        )
                        try? await Task.sleep(for: .seconds(backoff))
                        do {
                            try await self.taskQueue.requeue(task)
                        } catch {
                            self.logger.error("Failed to requeue rate-limited task \(task.id): \(error.localizedDescription)")
                        }
                    } else if self.retryPolicy.shouldRetry(task: task, error: error) {
                        let backoff = self.retryPolicy.backoffInterval(for: task.retryCount)
                        try? await Task.sleep(for: .seconds(backoff))
                        do {
                            try await self.taskQueue.requeue(task)
                        } catch {
                            self.logger.error("Failed to requeue retryable task \(task.id): \(error.localizedDescription)")
                        }
                    } else {
                        do {
                            try await self.taskQueue.fail(task, error: error.localizedDescription)
                        } catch {
                            self.logger.error("Failed to mark task \(task.id) as failed: \(error.localizedDescription)")
                        }

                        // In-app notification: task failed
                        await self.notificationService.emit(
                            category: .task,
                            severity: .error,
                            title: "Task Failed",
                            message: "\(task.title): \(error.localizedDescription)"
                        )

                        // Telegram notification: task failed (no more retries)
                        await self.sendTelegramNotification(for: task) { telegram, project in
                            await telegram.notifyTaskFailed(task: task, project: project)
                        }
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
        case .planner: return PlannerAgent()
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

    /// Set up a git branch for coder tasks (best-effort — git failures never block the task)
    private func setupCoderBranch(task: AgentTask) async {
        do {
            let project = try await dbQueue.read { db in
                try Project.fetchOne(db, id: task.projectId)
            }
            guard let project, !project.directoryPath.isEmpty else { return }
            _ = try await branchManager.setupFeatureBranch(task: task, in: project.directoryPath)
        } catch {
            print("[CreedFlow] Git branch setup failed for task \(task.id): \(error.localizedDescription)")
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

        // Universal auto-commit for non-coder tasks (coder has its own flow)
        if task.agentType != .coder {
            await autoCommitChanges(task: task)
        }

        // Universal merge: if task ran on a branch, merge it into dev
        // Re-read task from DB to get current branchName (parameter may be stale)
        let currentTask = (try? await dbQueue.read { db in
            try AgentTask.fetchOne(db, id: task.id)
        }) ?? task
        if let branchName = currentTask.branchName {
            await mergeTaskBranchToDev(branchName: branchName, projectId: task.projectId)
        }

        // Check if all tasks for this feature are done → promote dev → staging
        if let featureId = task.featureId {
            await checkFeatureCompletionAndPromote(featureId: featureId, projectId: task.projectId)
        }
    }

    /// Auto-commit any git changes after a task completes (best-effort).
    private func autoCommitChanges(task: AgentTask) async {
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        guard let project, !project.directoryPath.isEmpty else { return }
        _ = await branchManager.autoCommitIfNeeded(task: task, in: project.directoryPath)
    }

    /// Merge a task's branch into dev after completion (best-effort).
    /// This is the universal merge step — ensures every task's changes end up in dev,
    /// even if the GitHub PR flow failed or was skipped.
    private func mergeTaskBranchToDev(branchName: String, projectId: UUID) async {
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: projectId)
        }
        guard let project, !project.directoryPath.isEmpty else { return }
        await branchManager.mergeTaskBranchToDev(branchName: branchName, in: project.directoryPath)
    }

    /// Check if all tasks for a feature passed, merge dev → staging, and auto-create staging deployment.
    private func checkFeatureCompletionAndPromote(featureId: UUID, projectId: UUID) async {
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: projectId)
        }
        guard let project, !project.directoryPath.isEmpty else { return }
        let prNumber = await branchManager.checkFeatureCompletionAndPromote(
            featureId: featureId,
            projectId: projectId,
            in: project.directoryPath
        )

        // If dev → staging merge succeeded, auto-create staging deployment + DevOps task
        if let prNumber {
            await createStagingDeployment(projectId: projectId, projectName: project.name, version: "PR-\(prNumber)")
        }
    }

    /// Auto-create a staging deployment record and DevOps task to trigger the deploy.
    private func createStagingDeployment(projectId: UUID, projectName: String, version: String) async {
        do {
            // Don't create duplicate: check if there's already a pending/in-progress staging deploy
            let existing = try await dbQueue.read { db in
                try Deployment
                    .filter(Column("projectId") == projectId)
                    .filter(Column("environment") == Deployment.Environment.staging.rawValue)
                    .filter(Column("status") == Deployment.Status.pending.rawValue
                         || Column("status") == Deployment.Status.inProgress.rawValue)
                    .fetchOne(db)
            }
            guard existing == nil else { return }

            let deployment = Deployment(
                projectId: projectId,
                environment: .staging,
                version: version,
                deployedBy: "auto-promotion",
                port: 3001
            )

            let devopsTask = AgentTask(
                projectId: projectId,
                agentType: .devops,
                title: "Deploy: \(projectName) (staging)",
                description: "Automated staging deployment after all feature tasks passed and dev → staging merge completed.\nVersion: \(version)",
                priority: 10
            )

            try await dbQueue.write { [deployment, devopsTask] db in
                var d = deployment
                try d.insert(db)
                var t = devopsTask
                try t.insert(db)
            }

            try? await logInfo(
                taskId: devopsTask.id,
                agent: .devops,
                message: "Auto-created staging deployment for \(projectName) (version \(version))"
            )
        } catch {
            try? await logError(
                taskId: UUID(),
                agent: .devops,
                message: "Failed to create auto staging deployment: \(error.localizedDescription)"
            )
        }
    }

    /// Strip ANSI escape codes from CLI output (color codes, cursor movement, etc.)
    func stripANSI(_ text: String) -> String {
        // Matches sequences like \e[0m, \e[1;31m, \e[38;5;200m, etc.
        guard let regex = try? NSRegularExpression(pattern: "\\e\\[[0-9;]*[A-Za-z]") else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    /// Strip known CLI banners (Codex header, Gemini preamble, etc.) from output
    func stripCLIBanners(_ text: String) -> String {
        var result = text
        // Codex CLI banner: "OpenAI Codex vX.Y.Z (research preview)\n--------\n..."
        // Ends at a blank line after the key-value header block
        if result.hasPrefix("OpenAI Codex") || result.hasPrefix("Codex") {
            // Find the end of the banner (double newline or "--------" separator followed by key-value lines)
            let lines = result.components(separatedBy: "\n")
            var bannerEnd = 0
            var passedSeparator = false
            for (i, line) in lines.enumerated() {
                if line.hasPrefix("--------") { passedSeparator = true; continue }
                if passedSeparator && line.trimmingCharacters(in: .whitespaces).isEmpty {
                    bannerEnd = i + 1
                    break
                }
                if passedSeparator && !line.contains(":") && !line.isEmpty {
                    bannerEnd = i
                    break
                }
            }
            if bannerEnd > 0 && bannerEnd < lines.count {
                result = lines[bannerEnd...].joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }

    /// Extract JSON from text that might contain markdown code blocks or extra text
    func extractJSON(from rawText: String) -> Data? {
        let text = stripCLIBanners(stripANSI(rawText))

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

    func logError(taskId: UUID, agent: AgentTask.AgentType, message: String) async throws {
        try await dbQueue.write { db in
            let log = AgentLog(taskId: taskId, agentType: agent, level: .error, message: message)
            try log.insert(db)
        }
    }

    func logInfo(taskId: UUID, agent: AgentTask.AgentType, message: String) async throws {
        try await dbQueue.write { db in
            let log = AgentLog(taskId: taskId, agentType: agent, level: .info, message: message)
            try log.insert(db)
        }
    }

    // MARK: - Revision Memory

    /// Build contextual memory from previous attempts, reviews, and user instructions for retry tasks.
    private func buildRevisionMemory(for task: AgentTask) async -> String? {
        var sections: [String] = []

        // 1. Previous reviews for this task
        let reviews = try? await dbQueue.read { db in
            try Review
                .filter(Column("taskId") == task.id)
                .order(Column("createdAt").desc)
                .limit(3)
                .fetchAll(db)
        }
        if let reviews, !reviews.isEmpty {
            var reviewBlock = "## Previous Reviews"
            for review in reviews {
                reviewBlock += "\n- Score: \(review.score)/10 | Verdict: \(review.verdict.rawValue)"
                reviewBlock += "\n  Summary: \(review.summary)"
                if let issues = review.issues, !issues.isEmpty {
                    reviewBlock += "\n  Issues: \(issues)"
                }
                if let suggestions = review.suggestions, !suggestions.isEmpty {
                    reviewBlock += "\n  Suggestions: \(suggestions)"
                }
            }
            sections.append(reviewBlock)
        }

        // 2. Recent error/warning logs for this task
        let errorLogs = try? await dbQueue.read { db in
            try AgentLog
                .filter(Column("taskId") == task.id)
                .filter(Column("level") == "error" || Column("level") == "warning")
                .order(Column("createdAt").desc)
                .limit(10)
                .fetchAll(db)
        }
        if let errorLogs, !errorLogs.isEmpty {
            var logBlock = "## Previous Errors/Warnings"
            for log in errorLogs {
                logBlock += "\n- [\(log.level.rawValue.uppercased())] \(log.message)"
            }
            sections.append(logBlock)
        }

        // 3. Previous output (truncated)
        if let result = task.result, !result.isEmpty {
            let truncated = String(result.prefix(2000))
            sections.append("## Previous Output (truncated)\n\(truncated)")
        }

        // 4. User's custom revision instructions
        if let revisionPrompt = task.revisionPrompt, !revisionPrompt.isEmpty {
            sections.append("## User Revision Instructions\n\(revisionPrompt)")
        }

        guard !sections.isEmpty else { return nil }

        return """
        <revision_context>
        # REVISION CONTEXT — Attempt #\(task.retryCount)
        This task has been attempted before. Use the context below to avoid repeating mistakes and follow any user instructions.

        \(sections.joined(separator: "\n\n"))
        </revision_context>

        """
    }

    // MARK: - Telegram Notifications

    func sendTelegramNotification(
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
