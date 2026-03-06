import Foundation
import GRDB

// MARK: - Analyzer Completion Handler

extension Orchestrator {

    /// Parse analyzer JSON output and create features + tasks in DB
    func handleAnalyzerCompletion(task: AgentTask, result: AgentResult) async {
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
    func buildEnrichedTaskDescription(
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
    func saveAnalysisDocs(
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
    func updateProjectClaudeMD(
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
    func saveAnalyzerSkills(
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
}
