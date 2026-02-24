import Foundation

/// Parses project descriptions into structured task lists with dependency graphs.
/// Adapts decomposition strategy based on project type detected in the task description.
struct AnalyzerAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.analyzer

    let systemPrompt = """
        You are an expert project architect. Your job is to analyze a project description \
        and decompose it into features and implementation tasks.

        For each task, specify:
        - A clear, atomic title
        - Detailed description of what needs to be implemented
        - Priority (1-10, where 10 is highest)
        - Agent type needed (depends on project type — see instructions)
        - Dependencies on other tasks (by title reference)

        Output MUST be valid JSON matching the provided schema.
        Think step by step about the dependency graph — no circular dependencies allowed.
        """

    let allowedTools: [String]? = [] // No tools needed — pure text analysis
    let maxBudgetUSD: Double = 1.0
    let timeoutSeconds = 120 // 2 minutes is enough
    let streamOutput = true  // Show live progress in UI
    let backendPreferences: BackendPreferences = .anyBackend

    func buildPrompt(for task: AgentTask) -> String {
        let projectType = extractProjectType(from: task.description)
        let cleanDescription = removeProjectTypeTag(from: task.description)

        if isRevision(cleanDescription) {
            return buildRevisionPrompt(cleanDescription, projectType: projectType)
        }

        let strategy = decompositionStrategy(for: projectType)
        let agentTypes = allowedAgentTypes(for: projectType)

        return """
        Analyze the following project description and create a feature/task breakdown.
        Respond with ONLY a JSON object (no markdown, no explanation) in this exact format:

        {"projectName":"...","techStack":"...","features":[{"name":"...","description":"...","priority":1-10,"tasks":[{"title":"...","description":"...","agentType":"\(agentTypes)","priority":1-10,"dependsOn":["other task title"]}]}]}

        Keep it concise: max 5 features, max 4 tasks per feature.
        Priority 10 = highest. No circular dependencies.

        \(strategy)

        Project description:
        \(cleanDescription)
        """
    }

    // MARK: - Revision Support

    private func isRevision(_ description: String) -> Bool {
        description.contains("[REVISION]")
    }

    private func buildRevisionPrompt(_ description: String, projectType: Project.ProjectType) -> String {
        let strategy = decompositionStrategy(for: projectType)
        let agentTypes = allowedAgentTypes(for: projectType)

        // Parse existing features and new requirements from the description
        let parts = description.components(separatedBy: "NEW REQUIREMENTS:")
        let existingContext = parts.first?.replacingOccurrences(of: "[REVISION]", with: "").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newRequirements = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : description

        return """
        You are adding NEW features to an existing project. Do NOT duplicate any existing features.

        \(existingContext)

        IMPORTANT RULES:
        - Only create NEW features and tasks for the new requirements below
        - Do NOT recreate or duplicate any of the existing features listed above
        - New tasks may reference existing features as dependencies if needed
        - Keep the same JSON format as a fresh analysis

        Respond with ONLY a JSON object (no markdown, no explanation) in this exact format:

        {"projectName":"...","techStack":"...","features":[{"name":"...","description":"...","priority":1-10,"tasks":[{"title":"...","description":"...","agentType":"\(agentTypes)","priority":1-10,"dependsOn":["other task title"]}]}]}

        Keep it concise: max 5 features, max 4 tasks per feature.
        Priority 10 = highest. No circular dependencies.

        \(strategy)

        New requirements to add:
        \(newRequirements)
        """
    }

    // MARK: - Project Type Detection

    private func extractProjectType(from description: String) -> Project.ProjectType {
        // Look for [ProjectType: X] tag prepended by NewProjectSheet
        let pattern = "\\[ProjectType:\\s*(\\w+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
              let typeRange = Range(match.range(at: 1), in: description) else {
            return .software
        }
        let typeStr = String(description[typeRange]).lowercased()
        return Project.ProjectType(rawValue: typeStr) ?? .software
    }

    private func removeProjectTypeTag(from description: String) -> String {
        let pattern = "\\[ProjectType:\\s*\\w+\\]\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return description }
        return regex.stringByReplacingMatches(
            in: description,
            range: NSRange(description.startIndex..., in: description),
            withTemplate: ""
        )
    }

    // MARK: - Decomposition Strategies

    private func decompositionStrategy(for type: Project.ProjectType) -> String {
        switch type {
        case .software:
            return "Order: database/models first, then business logic, then UI, then tests."
        case .content:
            return """
            Order: research first, then outline, then draft writing, then editing/review.
            Focus on content structure, tone consistency, and audience targeting.
            """
        case .image:
            return """
            Order: concept/mood board first, then prompt engineering, then generation, then refinement.
            Focus on visual consistency, style guidelines, and iterative improvement.
            """
        case .video:
            return """
            Order: script first, then storyboard, then production planning, then editing specs.
            Focus on narrative flow, pacing, and technical specifications.
            """
        case .general:
            return "Use a flexible breakdown appropriate for the project description."
        }
    }

    private func allowedAgentTypes(for type: Project.ProjectType) -> String {
        switch type {
        case .software:
            return "coder|devops|tester"
        case .content:
            return "contentWriter|reviewer"
        case .image:
            return "imageGenerator|designer|reviewer"
        case .video:
            return "videoEditor|imageGenerator|contentWriter"
        case .general:
            return "coder|contentWriter|designer|imageGenerator|videoEditor|devops|tester|reviewer"
        }
    }
}
