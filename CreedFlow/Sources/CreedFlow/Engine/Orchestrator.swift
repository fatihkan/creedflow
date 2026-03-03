import Foundation
import AppKit
import GRDB

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
    private let dbQueue: DatabaseQueue
    private let taskQueue: TaskQueue
    private let scheduler: AgentScheduler
    private let processManager: ClaudeProcessManager
    let backendRouter: BackendRouter
    private let gitService: GitService
    private let gitHubService: GitHubService
    private let projectDirService: ProjectDirectoryService
    private let retryPolicy: RetryPolicy
    private let telegramService: TelegramBotService?
    private let localDeployService: LocalDeploymentService
    private let assetService: AssetStorageService
    private let thumbnailService: ThumbnailGeneratorService
    private let publishingService: ContentPublishingService
    private let contentExporter: ContentExporter
    private let branchManager: GitBranchManager
    private let preferencesStore = AgentBackendPreferencesStore()
    let notificationService: NotificationService
    let backendHealthMonitor: BackendHealthMonitor
    let mcpHealthMonitor: MCPHealthMonitor

    /// Agent types that require at least one creative MCP service to be configured
    private static let creativeAgentTypes: Set<AgentTask.AgentType> = [
        .imageGenerator, .videoEditor, .designer
    ]

    private(set) var isRunning = false
    private(set) var activeRunners: [UUID: MultiBackendRunner] = [:]
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

        // Register backends (done after init to avoid capturing self before init completes)
        // All three are registered; BackendRouter checks isEnabled + isAvailable before selection.
        let pm = self.processManager
        let claudeResolvedPath = resolvedPath
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
        // Fill all available scheduler slots in one cycle
        while true {
            // Try to dequeue a task
            guard let task = try? await taskQueue.dequeue() else { return }

            // Check if scheduler has a slot (non-blocking)
            let acquired = await scheduler.tryAcquire(task: task)
            guard acquired else {
                // Can't schedule now (no slot or coder conflict), defer without incrementing retryCount
                try? await taskQueue.deferTask(task)
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
                    try? await taskQueue.fail(
                        task,
                        error: "No creative AI service configured. Go to Settings \u{2192} MCP Servers to add an API key for \(serviceList)."
                    )
                    continue
                }
            }

            let effectivePrefs = preferencesStore.preferences(for: task.agentType)
            guard let backend = await backendRouter.selectBackend(preferences: effectivePrefs, task: task) else {
                // No enabled/available backend — defer the task back to queue
                await scheduler.release(task: task)
                try? await taskQueue.deferTask(task)
                continue  // No backend for THIS task, but others might have one
            }

            // Health-aware dispatch: skip unhealthy backends, defer task instead
            let healthStatus = await backendHealthMonitor.status(for: backend.backendType)
            if healthStatus == .unhealthy {
                await scheduler.release(task: task)
                try? await taskQueue.deferTask(task)
                continue
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

            // Dispatch in a Swift Task (fire-and-forget — loop continues immediately)
            Task { [weak self, agent, templateValues, recommendation] in
                defer {
                    Task { [weak self] in
                        await self?.scheduler.release(task: task)
                        self?.activeRunners.removeValue(forKey: task.id)
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

                        // Inject skill persona into prompt (enriched from Prompt table if available)
                        if let persona = task.skillPersona, !persona.isEmpty {
                            // Look up enriched skill content from Prompt table
                            let skillPrompt = try? await self.dbQueue.read { db in
                                try Prompt
                                    .filter(Column("category") == "skill")
                                    .filter(Column("content").like("%\(String(persona.prefix(50)))%"))
                                    .fetchOne(db)
                            }

                            let skillContent = skillPrompt?.content ?? persona
                            let personaPrefix = "<skill_persona>\nYou are: \(skillContent)\nApply this expertise throughout the task.\n</skill_persona>\n\n"
                            let base = promptOverride ?? agent.buildPrompt(for: task)
                            promptOverride = personaPrefix + base

                            // Record PromptUsage for skill tracking
                            if let prompt = skillPrompt {
                                try? await self.dbQueue.write { db in
                                    let usage = PromptUsage(
                                        promptId: prompt.id,
                                        projectId: task.projectId,
                                        taskId: task.id,
                                        agentType: task.agentType.rawValue
                                    )
                                    try usage.insert(db)
                                }
                            }
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
                        try? await self.taskQueue.requeue(task)
                    } else if self.retryPolicy.shouldRetry(task: task, error: error) {
                        let backoff = self.retryPolicy.backoffInterval(for: task.retryCount)
                        try? await Task.sleep(for: .seconds(backoff))
                        try? await self.taskQueue.requeue(task)
                    } else {
                        try? await self.taskQueue.fail(task, error: error.localizedDescription)

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
    private func stripANSI(_ text: String) -> String {
        // Matches sequences like \e[0m, \e[1;31m, \e[38;5;200m, etc.
        guard let regex = try? NSRegularExpression(pattern: "\\e\\[[0-9;]*[A-Za-z]") else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    /// Strip known CLI banners (Codex header, Gemini preamble, etc.) from output
    private func stripCLIBanners(_ text: String) -> String {
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
    private func extractJSON(from rawText: String) -> Data? {
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

    /// Parse analyzer JSON output and create features + tasks in DB
    private func handleAnalyzerCompletion(task: AgentTask, result: AgentResult) async {
        guard let output = result.output else {
            try? await logError(taskId: task.id, agent: .analyzer, message: "Analyzer returned no output")
            try? await taskQueue.fail(task, error: "Analyzer returned no output")
            return
        }

        guard let data = extractJSON(from: output) else {
            try? await logError(taskId: task.id, agent: .analyzer, message: "Could not extract JSON from analyzer output: \(output.prefix(200))")
            try? await taskQueue.fail(task, error: "Could not extract JSON from analyzer output")
            return
        }

        // Parse the structured JSON output (supports both rich and legacy formats)
        struct AnalyzerOutput: Decodable {
            let projectName: String?
            let techStack: String?
            let architecture: String?
            let dataModels: [AnalysisDataModel]?
            let diagrams: [AnalysisDiagram]?
            let configFiles: [ConfigFile]?
            let features: [FeatureOutput]

            struct ConfigFile: Decodable {
                let path: String
                let content: String
            }

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
                let acceptanceCriteria: [String]?
                let filesToCreate: [String]?
                let estimatedComplexity: String?
                let skillPersona: String?
            }
        }

        do {
            let parsed = try JSONDecoder().decode(AnalyzerOutput.self, from: data)

            // Fetch project for directory path
            let project = try await dbQueue.read { db in
                try Project.fetchOne(db, id: task.projectId)
            }

            // Update project tech stack if provided
            if let techStack = parsed.techStack {
                try await dbQueue.write { db in
                    guard var p = try Project.fetchOne(db, id: task.projectId) else { return }
                    p.techStack = techStack
                    p.status = .inProgress
                    p.updatedAt = Date()
                    try p.update(db)
                }
            }

            // Save architecture docs and diagrams to project directory
            if let project, !project.directoryPath.isEmpty {
                await saveAnalysisDocs(
                    to: project.directoryPath,
                    architecture: parsed.architecture,
                    dataModels: parsed.dataModels,
                    diagrams: parsed.diagrams,
                    taskId: task.id
                )

                // Write config files to project root
                if let configs = parsed.configFiles {
                    let fm = FileManager.default
                    for config in configs {
                        let filePath = "\(project.directoryPath)/\(config.path)"
                        let dir = (filePath as NSString).deletingLastPathComponent
                        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                        try? config.content.write(toFile: filePath, atomically: true, encoding: .utf8)
                    }
                }

                // Update CLAUDE.md with rich analyzer output
                let keyFiles = parsed.features.flatMap { $0.tasks.compactMap { $0.filesToCreate }.flatMap { $0 } }
                let uniqueKeyFiles = Array(Set(keyFiles)).sorted()
                await updateProjectClaudeMD(
                    projectDir: project.directoryPath,
                    project: project,
                    techStack: parsed.techStack,
                    architecture: parsed.architecture,
                    dataModels: parsed.dataModels,
                    keyFiles: uniqueKeyFiles,
                    taskId: task.id
                )
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

                        // Build enriched description with skill persona, acceptance criteria and file list
                        let enrichedDescription = buildEnrichedTaskDescription(
                            base: taskOutput.description,
                            acceptanceCriteria: taskOutput.acceptanceCriteria,
                            filesToCreate: taskOutput.filesToCreate,
                            estimatedComplexity: taskOutput.estimatedComplexity,
                            skillPersona: taskOutput.skillPersona
                        )

                        let newTask = AgentTask(
                            id: pregenId,
                            projectId: task.projectId,
                            featureId: feature.id,
                            agentType: agentType,
                            title: taskOutput.title,
                            description: enrichedDescription,
                            priority: taskOutput.priority,
                            skillPersona: taskOutput.skillPersona
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

            // Save skill prompts from analyzer output
            // Extract (taskTitle, skillPersona, agentType) tuples from parsed features
            var skillEntries: [(title: String, persona: String, agentType: String)] = []
            for feature in parsed.features {
                for taskOutput in feature.tasks {
                    if let persona = taskOutput.skillPersona, !persona.isEmpty {
                        skillEntries.append((title: taskOutput.title, persona: persona, agentType: taskOutput.agentType))
                    }
                }
            }
            await saveAnalyzerSkills(
                projectId: task.projectId,
                skillEntries: skillEntries,
                techStack: parsed.techStack,
                titleToTaskId: titleToTaskId
            )

            let totalTasks = titleToTaskId.count
            let diagramCount = parsed.diagrams?.count ?? 0
            let modelCount = parsed.dataModels?.count ?? 0
            let configCount = parsed.configFiles?.count ?? 0
            try? await logInfo(taskId: task.id, agent: .analyzer,
                             message: "Created \(parsed.features.count) features, \(totalTasks) tasks, \(modelCount) data models, \(diagramCount) diagrams, \(configCount) config files")

        } catch {
            try? await logError(taskId: task.id, agent: .analyzer,
                              message: "Failed to parse analyzer output: \(error.localizedDescription)")
        }
    }

    /// Build an enriched task description that includes skill persona, acceptance criteria and files to create.
    private func buildEnrichedTaskDescription(
        base: String,
        acceptanceCriteria: [String]?,
        filesToCreate: [String]?,
        estimatedComplexity: String?,
        skillPersona: String? = nil
    ) -> String {
        var parts: [String] = [base]

        if let persona = skillPersona, !persona.isEmpty {
            parts.append("\n--- Required Skill ---")
            parts.append("  \(persona)")
        }

        if let complexity = estimatedComplexity, !complexity.isEmpty {
            parts.append("\n[Complexity: \(complexity)]")
        }

        if let criteria = acceptanceCriteria, !criteria.isEmpty {
            parts.append("\n--- Acceptance Criteria ---")
            for (i, criterion) in criteria.enumerated() {
                parts.append("  \(i + 1). \(criterion)")
            }
        }

        if let files = filesToCreate, !files.isEmpty {
            parts.append("\n--- Files to Create/Modify ---")
            for file in files {
                parts.append("  - \(file)")
            }
        }

        return parts.joined(separator: "\n")
    }

    /// Save architecture documentation and Mermaid diagrams to project directory.
    private func saveAnalysisDocs(
        to projectDir: String,
        architecture: String?,
        dataModels: [AnalysisDataModel]?,
        diagrams: [AnalysisDiagram]?,
        taskId: UUID
    ) async {
        let fm = FileManager.default
        let docsDir = "\(projectDir)/docs"
        try? fm.createDirectory(atPath: docsDir, withIntermediateDirectories: true)

        // Save ARCHITECTURE.md
        if let arch = architecture, !arch.isEmpty {
            var content = "# Architecture\n\n\(arch)\n"

            // Append data models section
            if let models = dataModels, !models.isEmpty {
                content += "\n## Data Models\n\n"
                for model in models {
                    content += "### \(model.name)"
                    if let type = model.type { content += " (\(type))" }
                    content += "\n\n"
                    if let fields = model.fields {
                        content += "| Field | Type | Constraints |\n|-------|------|-------------|\n"
                        for field in fields {
                            content += "| \(field.name) | \(field.type) | \(field.constraints ?? "") |\n"
                        }
                        content += "\n"
                    }
                    if let rels = model.relationships, !rels.isEmpty {
                        content += "**Relationships:** \(rels.joined(separator: ", "))\n\n"
                    }
                }
            }

            let archPath = "\(docsDir)/ARCHITECTURE.md"
            try? content.write(toFile: archPath, atomically: true, encoding: .utf8)
        }

        // Save Mermaid diagrams
        if let diagrams, !diagrams.isEmpty {
            let diagramsDir = "\(docsDir)/diagrams"
            try? fm.createDirectory(atPath: diagramsDir, withIntermediateDirectories: true)

            for (index, diagram) in diagrams.enumerated() {
                let safeName = diagram.title
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "/", with: "-")
                let fileName = "\(index + 1)-\(safeName).mmd"
                let filePath = "\(diagramsDir)/\(fileName)"
                // Unescape \\n to actual newlines in Mermaid content
                let mermaidContent = diagram.mermaid.replacingOccurrences(of: "\\n", with: "\n")
                try? mermaidContent.write(toFile: filePath, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Update CLAUDE.md in the project directory with rich analyzer output.
    private func updateProjectClaudeMD(
        projectDir: String,
        project: Project,
        techStack: String?,
        architecture: String?,
        dataModels: [AnalysisDataModel]?,
        keyFiles: [String],
        taskId: UUID
    ) async {
        do {
            try await projectDirService.updateClaudeMDFromAnalysis(
                at: projectDir,
                project: project,
                techStack: techStack,
                architecture: architecture,
                dataModels: dataModels,
                keyFiles: keyFiles
            )
        } catch {
            try? await logError(taskId: taskId, agent: .analyzer,
                               message: "Failed to update CLAUDE.md: \(error.localizedDescription)")
        }
    }

    /// Save unique skill personas from analyzer output as Prompt records in the DB.
    private func saveAnalyzerSkills(
        projectId: UUID,
        skillEntries: [(title: String, persona: String, agentType: String)],
        techStack: String?,
        titleToTaskId: [String: UUID]
    ) async {
        guard !skillEntries.isEmpty else { return }

        // Deduplicate by persona content (multiple tasks may share the same persona)
        var seenPersonas: Set<String> = []
        var uniqueSkills: [(persona: String, taskTitles: [String], agentType: String)] = []

        for entry in skillEntries {
            let normalized = entry.persona.trimmingCharacters(in: .whitespacesAndNewlines)
            if seenPersonas.contains(normalized) {
                // Append task title to existing entry
                if let idx = uniqueSkills.firstIndex(where: { $0.persona == normalized }) {
                    uniqueSkills[idx].taskTitles.append(entry.title)
                }
            } else {
                seenPersonas.insert(normalized)
                uniqueSkills.append((persona: normalized, taskTitles: [entry.title], agentType: entry.agentType))
            }
        }

        for skill in uniqueSkills {
            // Build a short title from the persona (first line or first 60 chars)
            let shortName = skill.persona.components(separatedBy: "\n").first
                .map { $0.count > 60 ? String($0.prefix(60)) + "..." : $0 }
                ?? String(skill.persona.prefix(60))
            let skillTitle = "Skill: \(shortName)"

            // Build full content with tech stack context
            var content = skill.persona
            if let stack = techStack, !stack.isEmpty {
                content += "\n\nTech stack context: \(stack)"
            }

            do {
                try await dbQueue.write { db in
                    // Check for existing skill with same title (skip if duplicate)
                    let existing = try Prompt
                        .filter(Column("category") == "skill")
                        .filter(Column("title") == skillTitle)
                        .fetchOne(db)

                    let promptId: UUID
                    if let existing {
                        promptId = existing.id
                    } else {
                        let prompt = Prompt(
                            title: skillTitle,
                            content: content,
                            source: .user,
                            category: "skill",
                            isBuiltIn: false
                        )
                        try prompt.insert(db)
                        promptId = prompt.id
                    }

                    // Record PromptUsage for each task that uses this skill
                    for taskTitle in skill.taskTitles {
                        guard let taskId = titleToTaskId[taskTitle] else { continue }
                        let usage = PromptUsage(
                            promptId: promptId,
                            projectId: projectId,
                            taskId: taskId,
                            agentType: skill.agentType
                        )
                        try usage.insert(db)
                    }
                }
            } catch {
                // Non-critical — log but don't fail the analyzer completion
                try? await logError(taskId: UUID(), agent: .analyzer,
                                   message: "Failed to save skill prompt '\(skillTitle)': \(error.localizedDescription)")
            }
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
            try? await taskQueue.fail(task, error: "Reviewer returned no output")
            return
        }

        guard let data = extractJSON(from: output) else {
            try? await logError(taskId: task.id, agent: .reviewer, message: "Could not extract JSON from reviewer output: \(output.prefix(200))")
            try? await taskQueue.fail(task, error: "Could not extract structured review from output")
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
            if verdict == .pass {
                // Auto-merge the feature PR into dev
                await mergeCoderPROnReviewPass(reviewTaskId: task.id, projectId: task.projectId)
            } else {
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

    /// When a review passes, find the coder task's PR and merge it into dev.
    private func mergeCoderPROnReviewPass(reviewTaskId: UUID, projectId: UUID) async {
        do {
            // Find the coder task this review depends on
            let coderTask = try await dbQueue.read { db -> AgentTask? in
                let deps = try TaskDependency
                    .filter(Column("taskId") == reviewTaskId)
                    .fetchAll(db)
                for dep in deps {
                    if let task = try AgentTask.fetchOne(db, id: dep.dependsOnTaskId),
                       task.agentType == .coder, task.prNumber != nil {
                        return task
                    }
                }
                return nil
            }

            guard let coderTask, let prNumber = coderTask.prNumber else { return }

            let project = try await dbQueue.read { db in
                try Project.fetchOne(db, id: projectId)
            }
            guard let project, !project.directoryPath.isEmpty else { return }

            await branchManager.mergeFeatureToDev(prNumber: prNumber, in: project.directoryPath)
        } catch {
            // Best effort — logged inside branchManager
        }
    }

    private func handleCoderCompletion(task: AgentTask) async {
        // Check if this coder task is a deployment fix task — if so, handle redeploy
        let isDeployFix = await checkAndRedeployIfFixTask(task)
        if isDeployFix { return }  // Deploy fix tasks don't need review

        // Re-read task from DB to get current branchName and result
        // (the parameter is a stale copy from before setupCoderBranch set branchName)
        let currentTask = (try? await dbQueue.read { db in
            try AgentTask.fetchOne(db, id: task.id)
        }) ?? task

        // Commit + push + create PR targeting dev via branch manager
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: currentTask.projectId)
        }
        if let project, !project.directoryPath.isEmpty {
            _ = await branchManager.handleCoderBranchCompletion(task: currentTask, in: project.directoryPath)
        }

        // Always queue reviewer task for non-deploy-fix coder completions
        let reviewDescription: String
        if let branch = currentTask.branchName {
            reviewDescription = "Review the code changes in branch \(branch) for task: \(currentTask.title)"
        } else {
            reviewDescription = "Review the code changes for task: \(currentTask.title)\n\nResult:\n\(currentTask.result?.prefix(2000) ?? "No output")"
        }

        try? await dbQueue.write { [currentTask] db in
            let reviewTask = AgentTask(
                projectId: currentTask.projectId,
                featureId: currentTask.featureId,
                agentType: .reviewer,
                title: "Review: \(currentTask.title)",
                description: reviewDescription,
                priority: currentTask.priority + 1,
                branchName: currentTask.branchName
            )
            try reviewTask.insert(db)

            let dep = TaskDependency(taskId: reviewTask.id, dependsOnTaskId: currentTask.id)
            try dep.insert(db)
        }
    }

    // MARK: - Deployment Auto-Recovery

    /// Check if a completed coder task is linked to a failed deployment as a fix task.
    /// If the coder task passed, reset the deployment to pending and re-trigger it.
    /// Returns true if this task was a deployment fix task.
    @discardableResult
    private func checkAndRedeployIfFixTask(_ task: AgentTask) async -> Bool {
        // Find any deployment whose fixTaskId matches this task
        let deployment = try? await dbQueue.read { db in
            try Deployment
                .filter(Column("fixTaskId") == task.id)
                .fetchOne(db)
        }
        guard var deployment else { return false }

        // Re-read task from DB to get current status (parameter may be stale)
        let currentTask = try? await dbQueue.read { db in
            try AgentTask.fetchOne(db, id: task.id)
        }
        let taskStatus = currentTask?.status ?? task.status

        if taskStatus == .passed {
            // Fix succeeded — reset deployment to pending so the Orchestrator re-deploys
            try? await logInfo(
                taskId: task.id,
                agent: .coder,
                message: "Deployment fix passed — re-queuing deployment \(deployment.id) for redeploy"
            )

            deployment.status = .pending
            deployment.completedAt = nil
            deployment.logs = (deployment.logs ?? "") + "\n--- Fix applied (task \(task.id)) — retrying deployment ---\n"
            let updated = deployment

            try? await dbQueue.write { db in
                var d = updated
                try d.update(db)
            }

            // Queue a new DevOps task to actually run the deployment again
            let project = try? await dbQueue.read { db in
                try Project.fetchOne(db, id: deployment.projectId)
            }

            try? await dbQueue.write { [deployment] db in
                let redeployTask = AgentTask(
                    projectId: deployment.projectId,
                    agentType: .devops,
                    title: "Redeploy: \(project?.name ?? "project") (\(deployment.environment.rawValue))",
                    description: """
                        Retry deployment after fix was applied.
                        Previous failure was fixed by task \(task.id).
                        Deployment ID: \(deployment.id)
                        Method: \(deployment.deployMethod ?? "auto-detect")
                        Port: \(deployment.port.map(String.init) ?? "auto")
                        """,
                    priority: 10
                )
                try redeployTask.insert(db)

                // Redeploy depends on the fix task being done
                let dep = TaskDependency(taskId: redeployTask.id, dependsOnTaskId: task.id)
                try dep.insert(db)
            }
        } else {
            // Fix task itself failed — spawn another fix attempt (if under limit)
            let failLogs = task.errorMessage ?? task.result ?? "Coder fix task failed with no output"
            try? await logError(
                taskId: task.id,
                agent: .coder,
                message: "Deployment fix task failed — will attempt another fix if under limit"
            )
            await spawnDeploymentFixTask(deployment: deployment, errorLogs: failLogs)
        }

        return true
    }

    /// Maximum number of auto-fix attempts per deployment before giving up.
    private static let maxDeployAutoFixAttempts = 3

    /// Update deployment status after devops task completes, then run actual deployment (#30).
    /// If the deployment fails, automatically creates a Coder fix task using the error logs.
    private func handleDevOpsCompletion(task: AgentTask, result: AgentResult) async {
        do {
            // Re-read task from DB to get current status (the parameter is a stale copy
            // from before MultiBackendRunner updated it to .passed/.failed)
            let currentTask = try await dbQueue.read { db in
                try AgentTask.fetchOne(db, id: task.id)
            }
            let taskStatus = currentTask?.status ?? task.status

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

            // If devops agent task failed, mark deployment as failed and spawn fix task
            guard taskStatus == .passed else {
                let failLogs = task.errorMessage ?? result.output ?? "DevOps task failed with no output"
                deployment.status = .failed
                deployment.completedAt = Date()
                deployment.logs = failLogs
                let failedDeployment = deployment
                try await dbQueue.write { db in
                    var d = failedDeployment
                    try d.update(db)
                }
                await spawnDeploymentFixTask(deployment: deployment, errorLogs: failLogs)
                return
            }

            // Resolve project for directory path
            let project = try await dbQueue.read { db in
                try Project.fetchOne(db, id: task.projectId)
            }
            guard let project else { return }

            let port: Int
            if let existingPort = deployment.port {
                port = existingPort
            } else {
                switch deployment.environment {
                case .production: port = 3000
                case .staging: port = 3001
                case .development: port = 3002
                }
            }
            deployment.port = port

            // Run actual local deployment
            _ = try await localDeployService.deploy(
                project: project,
                deployment: deployment,
                port: port
            )

            // Mark deployment as successful
            deployment.status = .success
            deployment.completedAt = Date()
            try await dbQueue.write { db in
                var d = deployment
                try d.update(db)
            }

            try? await logInfo(taskId: task.id, agent: .devops,
                             message: "Local deployment completed on port \(port)")

            // After successful staging deploy, promote staging → main
            if deployment.environment == .staging {
                _ = await branchManager.promoteStagingToMain(
                    projectId: project.id,
                    version: deployment.version,
                    in: project.directoryPath
                )
            }

        } catch {
            // LocalDeploymentService already marks the deployment as .failed in its own
            // catch block before re-throwing, so we don't need to update the status here.
            // Just log and spawn the fix task.
            try? await logError(taskId: task.id, agent: .devops,
                              message: "Failed to deploy: \(error.localizedDescription)")
            await handleLocalDeployFailure(task: task, error: error)
        }
    }

    /// When local deployment fails, find the deployment record and spawn a coder fix task.
    private func handleLocalDeployFailure(task: AgentTask, error: Error) async {
        do {
            let deployment = try await dbQueue.read { db in
                try Deployment
                    .filter(Column("projectId") == task.projectId)
                    .filter(Column("status") == Deployment.Status.failed.rawValue)
                    .order(Column("createdAt").desc)
                    .fetchOne(db)
            }
            guard let deployment else { return }
            await spawnDeploymentFixTask(deployment: deployment, errorLogs: error.localizedDescription)
        } catch {
            // Non-critical — already logged above
        }
    }

    /// Create a Coder task to fix a failed deployment. The task description includes the full error logs
    /// so the coder agent has context to diagnose and fix the issue.
    private func spawnDeploymentFixTask(deployment: Deployment, errorLogs: String) async {
        // Guard: don't exceed max auto-fix attempts
        guard deployment.autoFixAttempts < Self.maxDeployAutoFixAttempts else {
            try? await dbQueue.write { [deployment] db in
                let log = AgentLog(
                    taskId: deployment.fixTaskId ?? UUID(),
                    agentType: .devops,
                    level: .error,
                    message: "Deployment \(deployment.id) exhausted \(Self.maxDeployAutoFixAttempts) auto-fix attempts — manual intervention required"
                )
                try log.insert(db)
            }
            return
        }

        // Guard: don't create duplicate fix task if one already exists and is still active
        if let existingFixId = deployment.fixTaskId {
            let existingTask = try? await dbQueue.read { db in
                try AgentTask.fetchOne(db, id: existingFixId)
            }
            if let existingTask, existingTask.status == .queued || existingTask.status == .inProgress {
                return // Fix task already in flight
            }
        }

        // Fetch project name for a descriptive title
        let projectName = (try? await dbQueue.read { db in
            try Project.fetchOne(db, id: deployment.projectId)?.name
        }) ?? "Unknown"

        let truncatedLogs = String(errorLogs.prefix(3000))
        let attempt = deployment.autoFixAttempts + 1

        do {
            let fixTask = AgentTask(
                projectId: deployment.projectId,
                agentType: .coder,
                title: "Fix deployment failure: \(projectName) (\(deployment.environment.rawValue)) [attempt \(attempt)]",
                description: """
                    The deployment for project "\(projectName)" to \(deployment.environment.rawValue) has failed.
                    Deployment method: \(deployment.deployMethod ?? "unknown")
                    Port: \(deployment.port.map(String.init) ?? "N/A")

                    ERROR LOGS:
                    \(truncatedLogs)

                    INSTRUCTIONS:
                    1. Analyze the error logs above to identify the root cause.
                    2. Fix the issue in the project source code (Dockerfile, package.json, config files, source code, etc.).
                    3. Ensure the project can build and run successfully.
                    4. Do NOT attempt to deploy — deployment will be triggered automatically after this fix passes.
                    """,
                priority: 10 // High priority — deployment is broken
            )

            try await dbQueue.write { [fixTask, deployment] db in
                var task = fixTask
                try task.insert(db)

                // Link fix task to deployment and increment attempt counter
                var d = deployment
                d.fixTaskId = task.id
                d.autoFixAttempts += 1
                try d.update(db)
            }

            try? await logInfo(
                taskId: fixTask.id,
                agent: .coder,
                message: "Auto-created fix task for failed deployment \(deployment.id) (attempt \(attempt)/\(Self.maxDeployAutoFixAttempts))"
            )
        } catch {
            try? await logError(
                taskId: UUID(),
                agent: .devops,
                message: "Failed to create deployment fix task: \(error.localizedDescription)"
            )
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
        guard let project else {
            try? await taskQueue.fail(task, error: "Project not found for creative task")
            return
        }

        do {
            try await extractAndSaveAssets(output: result.output, task: task, project: project, defaultAssetType: assetType)
            await queueCreativeReview(for: task)
        } catch {
            try? await logError(taskId: task.id, agent: task.agentType,
                               message: "Creative completion error: \(error.localizedDescription)")
            try? await taskQueue.fail(task, error: error.localizedDescription)
        }
    }

    /// Handle content writer completion — parse output with 3-tier strategy, save assets, generate format variants, queue publisher.
    private func handleContentWriterCompletion(task: AgentTask, result: AgentResult) async {
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        guard let project else {
            try? await taskQueue.fail(task, error: "Project not found for content writer task")
            return
        }

        do {
            let parsed = parseContentWriterOutput(rawOutput: result.output, task: task)
            let isRevision = task.retryCount > 0 || task.revisionPrompt != nil

            for asset in parsed.assets {
                let logicalName = asset.name.contains(".") ? asset.name : "\(asset.name).md"

                let (parentId, version) = await resolveVersionInfo(
                    logicalName: logicalName, project: project, task: task, isRevision: isRevision
                )

                var savedAsset = try await assetService.saveTextAsset(
                    content: asset.content,
                    fileName: logicalName,
                    project: project,
                    task: task,
                    assetType: .document,
                    mimeType: "text/markdown",
                    parentAssetId: parentId,
                    version: version
                )

                // Save metadata if available
                if let metadata = parsed.metadata {
                    let metadataJSON = try? JSONSerialization.data(withJSONObject: metadata)
                    let metadataStr = metadataJSON.flatMap { String(data: $0, encoding: .utf8) }
                    if metadataStr != nil {
                        try await dbQueue.write { db in
                            savedAsset.metadata = metadataStr
                            savedAsset.updatedAt = Date()
                            try savedAsset.update(db)
                        }
                    }
                }
            }

            await generateThumbnailsForTask(taskId: task.id, projectName: project.name)

            // Scan for image placeholders and queue ImageGenerator tasks
            for asset in parsed.assets {
                await scanAndQueueImages(content: asset.content, task: task, project: project)
            }

            // Generate format variants (.txt, .html, .pdf, .docx) from saved .md assets
            await generateFormatVariants(task: task, project: project)

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

            try? await logInfo(taskId: task.id, agent: .contentWriter,
                              message: "Saved \(parsed.assets.count) document(s) via \(parsed.parseMethod) parsing")
        } catch {
            try? await logError(taskId: task.id, agent: .contentWriter,
                               message: "Content writer completion error: \(error.localizedDescription)")
        }
    }

    // MARK: - Content Writer Parsing

    /// Result of parsing ContentWriter output.
    private struct ContentWriterParsedOutput {
        struct DocumentAsset {
            let name: String
            let content: String
        }
        let assets: [DocumentAsset]
        let metadata: [String: Any]?
        let parseMethod: String  // "json", "yaml", "raw"
    }

    /// Parse ContentWriter output with 3-tier fallback: JSON → YAML front matter → raw markdown.
    private func parseContentWriterOutput(rawOutput: String?, task: AgentTask) -> ContentWriterParsedOutput {
        guard let output = rawOutput, !output.isEmpty else {
            return ContentWriterParsedOutput(assets: [], metadata: nil, parseMethod: "empty")
        }

        let cleaned = stripCLIBanners(stripANSI(output))

        // Tier 1: Try JSON {"assets": [...]} format
        if let data = extractJSON(from: cleaned) {
            struct AssetOutput: Decodable {
                let assets: [AssetItem]?
                struct AssetItem: Decodable {
                    let type: String?
                    let name: String?
                    let content: String?
                }
            }
            if let parsed = try? JSONDecoder().decode(AssetOutput.self, from: data),
               let items = parsed.assets, !items.isEmpty {
                let documents = items.compactMap { item -> ContentWriterParsedOutput.DocumentAsset? in
                    guard let content = item.content, !content.isEmpty else { return nil }
                    let name = item.name ?? "\(sanitize(task.title)).md"
                    return ContentWriterParsedOutput.DocumentAsset(name: name, content: content)
                }
                if !documents.isEmpty {
                    return ContentWriterParsedOutput(assets: documents, metadata: nil, parseMethod: "json")
                }
            }
        }

        // Tier 2: Try YAML front matter (---\n...\n---\ncontent)
        if let yamlResult = parseYAMLFrontMatter(cleaned, task: task) {
            return yamlResult
        }

        // Tier 3: Raw markdown fallback — wrap entire output as a single document asset
        let content = extractContentFromRawOutput(cleaned)
        let name = "\(sanitize(task.title)).md"
        let asset = ContentWriterParsedOutput.DocumentAsset(name: name, content: content)
        return ContentWriterParsedOutput(assets: [asset], metadata: nil, parseMethod: "raw")
    }

    /// Parse YAML front matter from content. Returns nil if no front matter found.
    private func parseYAMLFrontMatter(_ text: String, task: AgentTask) -> ContentWriterParsedOutput? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }

        // Find closing ---
        let afterFirst = trimmed.index(trimmed.startIndex, offsetBy: 3)
        let rest = String(trimmed[afterFirst...]).trimmingCharacters(in: .newlines)
        guard let closingRange = rest.range(of: "\n---") else { return nil }

        let yamlBlock = String(rest[rest.startIndex..<closingRange.lowerBound])
        let markdownBody = String(rest[closingRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !markdownBody.isEmpty else { return nil }

        // Parse simple YAML key-value pairs
        var metadata: [String: Any] = [:]
        var name: String?
        for line in yamlBlock.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)

            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            // Parse arrays like ["tag1", "tag2"]
            if value.hasPrefix("[") && value.hasSuffix("]") {
                let inner = String(value.dropFirst().dropLast())
                let items = inner.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
                metadata[key] = items
            } else {
                metadata[key] = value
            }

            if key == "name" {
                name = value
            } else if key == "title" && name == nil {
                name = sanitize(value) + ".md"
            }
        }

        let fileName = name ?? "\(sanitize(task.title)).md"

        // Count words
        let wordCount = markdownBody.split(whereSeparator: { $0.isWhitespace }).count
        metadata["wordCount"] = wordCount
        metadata["author"] = metadata["author"] ?? "CreedFlow"

        let asset = ContentWriterParsedOutput.DocumentAsset(name: fileName, content: markdownBody)
        return ContentWriterParsedOutput(assets: [asset], metadata: metadata, parseMethod: "yaml")
    }

    /// Scan content for creedflow:image:slug placeholders and queue ImageGenerator tasks.
    private func scanAndQueueImages(content: String, task: AgentTask, project: Project) async {
        let pattern = "!\\[([^\\]]*)\\]\\(creedflow:image:([a-z0-9-]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        guard !matches.isEmpty else { return }

        for match in matches {
            guard let descRange = Range(match.range(at: 1), in: content),
                  let slugRange = Range(match.range(at: 2), in: content) else { continue }

            let description = String(content[descRange])
            let slug = String(content[slugRange])

            do {
                try await dbQueue.write { db in
                    let imageTask = AgentTask(
                        projectId: task.projectId,
                        featureId: task.featureId,
                        agentType: .imageGenerator,
                        title: "Generate image: \(slug)",
                        description: "Generate an image for content placeholder. Description: \(description). Slug: \(slug). Parent content task: \(task.id)",
                        priority: task.priority
                    )
                    try imageTask.insert(db)

                    let dep = TaskDependency(taskId: imageTask.id, dependsOnTaskId: task.id)
                    try dep.insert(db)
                }
            } catch {
                try? await logError(taskId: task.id, agent: .contentWriter,
                                   message: "Failed to queue image task for slug '\(slug)': \(error.localizedDescription)")
            }
        }

        try? await logInfo(taskId: task.id, agent: .contentWriter,
                          message: "Queued \(matches.count) image generation task(s)")
    }

    /// Generate .txt, .html, .pdf, .docx format variants from .md document assets.
    private func generateFormatVariants(task: AgentTask, project: Project) async {
        let mdAssets: [GeneratedAsset] = (try? await dbQueue.read { db in
            try GeneratedAsset
                .filter(Column("taskId") == task.id)
                .filter(Column("assetType") == GeneratedAsset.AssetType.document.rawValue)
                .filter(Column("mimeType") == "text/markdown")
                .fetchAll(db)
        }) ?? []

        guard !mdAssets.isEmpty else { return }

        var variantCount = 0
        for mdAsset in mdAssets {
            let baseName = (mdAsset.name as NSString).deletingPathExtension
            let title = baseName.replacingOccurrences(of: "-", with: " ").capitalized

            // .txt — plaintext
            do {
                let exported = try await contentExporter.export(filePath: mdAsset.filePath, title: title, format: .plaintext)
                let fileName = "\(baseName).txt"
                _ = try await assetService.saveTextAsset(
                    content: exported.body,
                    fileName: fileName,
                    project: project,
                    task: task,
                    assetType: .document,
                    mimeType: "text/plain"
                )
                variantCount += 1
            } catch {
                try? await logError(taskId: task.id, agent: .contentWriter,
                                   message: "Failed to generate .txt variant: \(error.localizedDescription)")
            }

            // .html — styled HTML
            do {
                let exported = try await contentExporter.export(filePath: mdAsset.filePath, title: title, format: .html)
                let fileName = "\(baseName).html"
                _ = try await assetService.saveTextAsset(
                    content: exported.body,
                    fileName: fileName,
                    project: project,
                    task: task,
                    assetType: .document,
                    mimeType: "text/html"
                )
                variantCount += 1
            } catch {
                try? await logError(taskId: task.id, agent: .contentWriter,
                                   message: "Failed to generate .html variant: \(error.localizedDescription)")
            }

            // .pdf — rendered PDF via HTML
            do {
                let exported = try await contentExporter.export(filePath: mdAsset.filePath, title: title, format: .pdf)
                let pdfData = try await renderHTMLToPDF(html: exported.body, title: title)
                let fileName = "\(baseName).pdf"
                let dir = assetsDirectory(for: project)
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let pdfPath = (dir as NSString).appendingPathComponent(fileName)
                try pdfData.write(to: URL(fileURLWithPath: pdfPath))

                var pdfAsset = GeneratedAsset(
                    projectId: project.id,
                    taskId: task.id,
                    agentType: task.agentType,
                    assetType: .document,
                    name: fileName,
                    filePath: pdfPath,
                    mimeType: "application/pdf",
                    fileSize: Int64(pdfData.count)
                )
                try await dbQueue.write { db in
                    try pdfAsset.insert(db)
                }
                variantCount += 1
            } catch {
                try? await logError(taskId: task.id, agent: .contentWriter,
                                   message: "Failed to generate .pdf variant: \(error.localizedDescription)")
            }

            // .docx — Office Open XML
            do {
                let docxData = try await contentExporter.exportDOCX(filePath: mdAsset.filePath, title: title)
                let fileName = "\(baseName).docx"
                let dir = assetsDirectory(for: project)
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let docxPath = (dir as NSString).appendingPathComponent(fileName)
                try docxData.write(to: URL(fileURLWithPath: docxPath))

                var docxAsset = GeneratedAsset(
                    projectId: project.id,
                    taskId: task.id,
                    agentType: task.agentType,
                    assetType: .document,
                    name: fileName,
                    filePath: docxPath,
                    mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    fileSize: Int64(docxData.count)
                )
                try await dbQueue.write { db in
                    try docxAsset.insert(db)
                }
                variantCount += 1
            } catch {
                try? await logError(taskId: task.id, agent: .contentWriter,
                                   message: "Failed to generate .docx variant: \(error.localizedDescription)")
            }
        }

        if variantCount > 0 {
            await generateThumbnailsForTask(taskId: task.id, projectName: project.name)
            try? await logInfo(taskId: task.id, agent: .contentWriter,
                              message: "Generated \(variantCount) format variant(s) from \(mdAssets.count) document(s)")
        }
    }

    /// Render HTML string to PDF data using NSAttributedString.
    private func renderHTMLToPDF(html: String, title: String) async throws -> Data {
        try await MainActor.run {
            guard let htmlData = html.data(using: .utf8),
                  let attrString = NSAttributedString(
                      html: htmlData,
                      options: [.documentType: NSAttributedString.DocumentType.html,
                                .characterEncoding: String.Encoding.utf8.rawValue],
                      documentAttributes: nil
                  ) else {
                throw NSError(domain: "ContentExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse HTML"])
            }

            let printInfo = NSPrintInfo()
            printInfo.paperSize = NSSize(width: 612, height: 792) // US Letter
            printInfo.topMargin = 72
            printInfo.bottomMargin = 72
            printInfo.leftMargin = 72
            printInfo.rightMargin = 72
            printInfo.isVerticallyCentered = false

            let textStorage = NSTextStorage(attributedString: attrString)
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)

            let printableWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
            let printableHeight = printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin
            let textContainer = NSTextContainer(size: NSSize(width: printableWidth, height: printableHeight))
            layoutManager.addTextContainer(textContainer)

            // Force layout
            layoutManager.ensureLayout(for: textContainer)

            let pdfData = NSMutableData()
            let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
            var mediaBox = CGRect(x: 0, y: 0, width: printInfo.paperSize.width, height: printInfo.paperSize.height)
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                throw NSError(domain: "ContentExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context"])
            }

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)

            // Calculate pages
            let totalHeight = usedRect.height
            var pageOriginY: CGFloat = 0

            while pageOriginY < totalHeight {
                context.beginPDFPage(nil)
                context.saveGState()
                context.translateBy(x: printInfo.leftMargin, y: printInfo.paperSize.height - printInfo.topMargin)
                context.scaleBy(x: 1, y: -1)
                context.translateBy(x: 0, y: -pageOriginY) // Removed extra negation

                let visibleRange = layoutManager.glyphRange(
                    forBoundingRect: CGRect(x: 0, y: pageOriginY, width: printableWidth, height: printableHeight),
                    in: textContainer
                )

                let nsGraphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
                NSGraphicsContext.current = nsGraphicsContext
                layoutManager.drawGlyphs(forGlyphRange: visibleRange, at: CGPoint(x: 0, y: -pageOriginY))
                NSGraphicsContext.current = nil

                context.restoreGState()
                context.endPDFPage()
                pageOriginY += printableHeight
            }

            context.closePDF()
            return pdfData as Data
        }
    }

    private func assetsDirectory(for project: Project) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/CreedFlow/projects/\(project.name)/assets"
    }

    /// Handle publisher agent completion — parse publication plan and create records.
    private func handlePublisherCompletion(task: AgentTask, result: AgentResult) async {
        guard let output = result.output else {
            try? await logError(taskId: task.id, agent: .publisher, message: "Publisher returned no output")
            try? await taskQueue.fail(task, error: "Publisher returned no output")
            return
        }

        guard let data = extractJSON(from: output) else {
            try? await logInfo(taskId: task.id, agent: .publisher, message: "No structured publication plan in output")
            try? await taskQueue.fail(task, error: "Could not extract publication plan from output")
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
    /// Automatically links to previous versions when the task has been retried (retryCount > 0).
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

        let isRevision = task.retryCount > 0 || task.revisionPrompt != nil

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
                    let logicalName = name.contains(".") ? name : "\(name).\(extensionForAssetType(assetType))"

                    // Resolve version chain
                    let (parentId, version) = await resolveVersionInfo(
                        logicalName: logicalName, project: project, task: task, isRevision: isRevision
                    )

                    if let urlStr = item.url, let url = URL(string: urlStr) {
                        _ = try await assetService.downloadAndSaveAsset(
                            url: url,
                            fileName: logicalName,
                            project: project,
                            task: task,
                            assetType: assetType,
                            parentAssetId: parentId,
                            version: version
                        )
                    } else if let path = item.filePath, FileManager.default.fileExists(atPath: path) {
                        _ = try await assetService.recordExistingAsset(
                            filePath: path,
                            project: project,
                            task: task,
                            assetType: assetType,
                            parentAssetId: parentId,
                            version: version
                        )
                    } else if let content = item.content {
                        _ = try await assetService.saveTextAsset(
                            content: content,
                            fileName: logicalName,
                            project: project,
                            task: task,
                            assetType: assetType,
                            parentAssetId: parentId,
                            version: version
                        )
                    }
                }

                // Generate thumbnails for saved assets
                await generateThumbnailsForTask(taskId: task.id, projectName: project.name)

                let versionNote = isRevision ? " (revision)" : ""
                try? await logInfo(taskId: task.id, agent: task.agentType,
                                  message: "Saved \(items.count) asset(s)\(versionNote)")
                return
            }
        }

        // Fallback: try to extract meaningful content from raw output
        let sanitizedTitle = sanitize(task.title)
        let fallbackContent = extractContentFromRawOutput(output)
        let ext = extensionForAssetType(defaultAssetType)
        let fileName = sanitizedTitle.isEmpty
            ? "\(task.agentType.rawValue)-\(task.id.uuidString.prefix(8)).\(ext)"
            : "\(sanitizedTitle).\(ext)"

        let (parentId, version) = await resolveVersionInfo(
            logicalName: fileName, project: project, task: task, isRevision: isRevision
        )

        _ = try await assetService.saveTextAsset(
            content: fallbackContent,
            fileName: fileName,
            project: project,
            task: task,
            assetType: defaultAssetType,
            parentAssetId: parentId,
            version: version
        )
        // Generate thumbnail for the fallback asset
        await generateThumbnailsForTask(taskId: task.id, projectName: project.name)

        try? await logInfo(taskId: task.id, agent: task.agentType,
                          message: "Saved output as \(fileName) v\(version) (fallback)")
    }

    /// Resolve parentAssetId and version for a new asset being saved.
    /// When the task is a revision, look for a previous version by the same logical name.
    private func resolveVersionInfo(
        logicalName: String,
        project: Project,
        task: AgentTask,
        isRevision: Bool
    ) async -> (parentId: UUID?, version: Int) {
        guard isRevision else { return (nil, 1) }

        // First check: same task produced an earlier version with the same name
        if let previous = try? await assetService.latestAsset(forTaskId: task.id, name: logicalName) {
            return (previous.id, previous.version + 1)
        }

        // Second check: same project+agent produced an asset with this name in a previous task
        if let previous = try? await assetService.previousAssets(
            forProjectId: project.id, agentType: task.agentType, name: logicalName
        ) {
            return (previous.id, previous.version + 1)
        }

        return (nil, 1)
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

    private func extensionForAssetType(_ type: GeneratedAsset.AssetType) -> String {
        switch type {
        case .image: return "png"
        case .video: return "mp4"
        case .audio: return "mp3"
        case .design: return "json"
        case .document: return "md"
        }
    }

    /// Try to extract clean content from raw agent output that failed JSON parsing.
    /// Strips markdown fences, JSON fragments, and system noise to find the actual content.
    private func extractContentFromRawOutput(_ output: String) -> String {
        var text = output

        // Strip markdown code fences that may wrap the content
        let fencePattern = "```(?:json|markdown|md)?\\s*\\n([\\s\\S]*?)\\n```"
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let contentRange = Range(match.range(at: 1), in: text) {
            text = String(text[contentRange])
        }

        // If the output looks like a partial JSON with a "content" field, extract it
        let contentFieldPattern = "\"content\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        if let regex = try? NSRegularExpression(pattern: contentFieldPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let valueRange = Range(match.range(at: 1), in: text) {
            let extracted = String(text[valueRange])
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
                .replacingOccurrences(of: "\\\"", with: "\"")
            if extracted.count > 100 { // Only use if substantial content was extracted
                return extracted
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
