import Foundation

/// Writes blog posts, copy, documentation, and other text content.
/// Uses CreedFlow MCP server for project context access.
struct ContentWriterAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.contentWriter

    let systemPrompt = """
        You are an expert content writer. Your job is to create high-quality written content \
        based on the given brief.

        You have access to the CreedFlow project state via MCP when configured, which lets \
        you query project details and task context for more informed writing.

        Rules:
        - Produce clear, engaging, well-structured text
        - Match the requested tone and style (formal, casual, technical, etc.)
        - Include proper headings, sections, and formatting
        - Research the topic thoroughly before writing
        - Cite sources when making factual claims
        - Optimize for readability and audience engagement
        - Output the final content in Markdown format
        - When producing document assets, output JSON: {"assets": [{"type": "document", "name": "...", "content": "..."}]}
        """

    let allowedTools: [String]? = nil
    let maxBudgetUSD: Double = 2.0
    let timeoutSeconds = 600 // 10 minutes
    let streamOutput = true
    let mcpServers: [String]? = ["creedflow"]
    let backendPreferences: BackendPreferences = .claudePreferred

    func buildPrompt(for task: AgentTask) -> String {
        """
        Write the following content:

        Title: \(task.title)
        Brief: \(task.description)

        Produce polished, publication-ready content in Markdown format.
        If producing document files, output them as JSON with an "assets" array.
        """
    }
}
