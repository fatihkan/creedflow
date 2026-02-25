import Foundation
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
    private let branchManager: GitBranchManager

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
        self.branchManager = GitBranchManager(
            gitService: self.gitService,
            gitHubService: self.gitHubService,
            dbQueue: dbQueue
        )

        // Register backends (done after init to avoid capturing self before init completes)
        // All three are registered; BackendRouter checks isEnabled + isAvailable before selection.
        let pm = self.processManager
        let claudeResolvedPath = resolvedPath
        Task {
            await router.register(ClaudeBackend(processManager: pm, claudePath: claudeResolvedPath))
            await router.register(CodexBackend())
            await router.register(GeminiBackend())
            await router.register(OpenCodeBackend())
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
        guard let project, !project.directoryPath.isEmpty else { return }

        _ = try await branchManager.setupFeatureBranch(task: task, in: project.directoryPath)
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

    /// Check if all tasks for a feature passed and create a dev → staging PR.
    private func checkFeatureCompletionAndPromote(featureId: UUID, projectId: UUID) async {
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: projectId)
        }
        guard let project, !project.directoryPath.isEmpty else { return }
        _ = await branchManager.checkFeatureCompletionAndPromote(
            featureId: featureId,
            projectId: projectId,
            in: project.directoryPath
        )
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

        // Parse the structured JSON output (supports both rich and legacy formats)
        struct AnalyzerOutput: Decodable {
            let projectName: String?
            let techStack: String?
            let architecture: String?
            let dataModels: [AnalysisDataModel]?
            let diagrams: [AnalysisDiagram]?
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
                let acceptanceCriteria: [String]?
                let filesToCreate: [String]?
                let estimatedComplexity: String?
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

                        // Build enriched description with acceptance criteria and file list
                        let enrichedDescription = buildEnrichedTaskDescription(
                            base: taskOutput.description,
                            acceptanceCriteria: taskOutput.acceptanceCriteria,
                            filesToCreate: taskOutput.filesToCreate,
                            estimatedComplexity: taskOutput.estimatedComplexity
                        )

                        let newTask = AgentTask(
                            id: pregenId,
                            projectId: task.projectId,
                            featureId: feature.id,
                            agentType: agentType,
                            title: taskOutput.title,
                            description: enrichedDescription,
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
            let diagramCount = parsed.diagrams?.count ?? 0
            let modelCount = parsed.dataModels?.count ?? 0
            try? await logInfo(taskId: task.id, agent: .analyzer,
                             message: "Created \(parsed.features.count) features, \(totalTasks) tasks, \(modelCount) data models, \(diagramCount) diagrams")

        } catch {
            try? await logError(taskId: task.id, agent: .analyzer,
                              message: "Failed to parse analyzer output: \(error.localizedDescription)")
        }
    }

    /// Build an enriched task description that includes acceptance criteria and files to create.
    private func buildEnrichedTaskDescription(
        base: String,
        acceptanceCriteria: [String]?,
        filesToCreate: [String]?,
        estimatedComplexity: String?
    ) -> String {
        var parts: [String] = [base]

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

        // Commit + push + create PR targeting dev via branch manager
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: task.projectId)
        }
        if let project, !project.directoryPath.isEmpty {
            _ = await branchManager.handleCoderBranchCompletion(task: task, in: project.directoryPath)
        }

        // Always queue reviewer task for non-deploy-fix coder completions
        let reviewDescription: String
        if let branch = task.branchName {
            reviewDescription = "Review the code changes in branch \(branch) for task: \(task.title)"
        } else {
            reviewDescription = "Review the code changes for task: \(task.title)\n\nResult:\n\(task.result?.prefix(2000) ?? "No output")"
        }

        try? await dbQueue.write { db in
            let reviewTask = AgentTask(
                projectId: task.projectId,
                featureId: task.featureId,
                agentType: .reviewer,
                title: "Review: \(task.title)",
                description: reviewDescription,
                priority: task.priority + 1,
                branchName: task.branchName
            )
            try reviewTask.insert(db)

            let dep = TaskDependency(taskId: reviewTask.id, dependsOnTaskId: task.id)
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
                .filter(Column("fixTaskId") == task.id.uuidString)
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
