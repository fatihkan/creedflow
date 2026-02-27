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

        OUTPUT FORMAT — MANDATORY:
        You MUST output your final result as a JSON object. No markdown fences, no explanation \
        outside the JSON. The JSON must follow this exact schema:

        {
          "assets": [
            {
              "type": "document",
              "name": "kebab-case-title.md",
              "content": "# Full Markdown Content\\n\\nYour complete article here..."
            }
          ]
        }

        Rules for the JSON output:
        - "type" MUST be "document"
        - "name" MUST be kebab-case with .md extension (e.g. "seo-guide-2026.md")
        - "content" MUST contain the FULL text in Markdown format, not a summary or excerpt
        - For multi-part content (e.g. a blog series), include multiple items in the assets array
        - Each asset must be a complete, standalone piece of content
        - Do NOT wrap the JSON in markdown code fences
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

        Produce polished, publication-ready content. Write the FULL article — not an outline or summary.

        You MUST respond with ONLY a JSON object (no other text) in this format:
        {
          "assets": [
            {
              "type": "document",
              "name": "\(sanitize(task.title)).md",
              "content": "# Your Title\\n\\nFull markdown content here..."
            }
          ]
        }
        """
    }

    private func sanitize(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(50)
            .description
    }
}
