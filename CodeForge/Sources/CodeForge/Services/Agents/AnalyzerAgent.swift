import Foundation

/// Parses project descriptions into structured task lists with dependency graphs.
struct AnalyzerAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.analyzer

    let systemPrompt = """
        You are an expert software architect. Your job is to analyze a project description \
        and decompose it into features and implementation tasks.

        For each task, specify:
        - A clear, atomic title
        - Detailed description of what needs to be implemented
        - Priority (1-10, where 10 is highest)
        - Agent type needed (coder, devops, tester)
        - Dependencies on other tasks (by title reference)

        Output MUST be valid JSON matching the provided schema.
        Think step by step about the dependency graph — no circular dependencies allowed.
        Order tasks so that foundational work (database schema, models, configuration) comes first, \
        followed by business logic, then UI, then tests.
        """

    let allowedTools: [String]? = [] // No tools needed — pure text analysis
    let maxBudgetUSD: Double = 1.0
    let timeoutSeconds = 120 // 2 minutes is enough
    let streamOutput = true  // Show live progress in UI

    func buildPrompt(for task: AgentTask) -> String {
        """
        Analyze the following project description and create a feature/task breakdown.
        Respond with ONLY a JSON object (no markdown, no explanation) in this exact format:

        {"projectName":"...","techStack":"...","features":[{"name":"...","description":"...","priority":1-10,"tasks":[{"title":"...","description":"...","agentType":"coder|devops|tester","priority":1-10,"dependsOn":["other task title"]}]}]}

        Keep it concise: max 5 features, max 4 tasks per feature.
        Priority 10 = highest. No circular dependencies.
        Order: database/models first, then logic, then UI, then tests.

        Project description:
        \(task.description)
        """
    }
}
