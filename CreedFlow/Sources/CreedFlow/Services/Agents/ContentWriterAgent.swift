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
        - Where an image would enhance the content, insert a placeholder: \
        ![description](creedflow:image:kebab-case-slug) — these will be replaced with generated images

        OUTPUT FORMAT — PREFERRED (JSON):
        Output your final result as a JSON object. No markdown fences, no explanation outside the JSON:

        {
          "assets": [
            {
              "type": "document",
              "name": "kebab-case-title.md",
              "content": "# Full Markdown Content\\n\\nYour complete article here..."
            }
          ]
        }

        ALTERNATIVE FORMAT (YAML front matter + Markdown):
        If JSON output is difficult, you may use YAML front matter followed by Markdown:

        ---
        title: "Your Article Title"
        name: "kebab-case-title.md"
        tags: ["tag1", "tag2"]
        summary: "A brief summary of the article"
        ---

        # Full Markdown Content

        Your complete article here...

        LAST RESORT:
        If neither JSON nor YAML front matter is possible, output plain Markdown directly. \
        The system will automatically wrap it as a document asset.

        Rules for JSON output:
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
    let mcpServers: [String]? = ["creedflow", "notebooklm"]
    let backendPreferences: BackendPreferences = .claudePreferred

    func buildPrompt(for task: AgentTask) -> String {
        """
        Write the following content:

        Title: \(task.title)
        Brief: \(task.description)

        Produce polished, publication-ready content. Write the FULL article — not an outline or summary.
        Where images would enhance the content, insert: ![description](creedflow:image:slug)

        PREFERRED — respond with JSON:
        {
          "assets": [
            {
              "type": "document",
              "name": "\(sanitize(task.title)).md",
              "content": "# Your Title\\n\\nFull markdown content here..."
            }
          ]
        }

        ALTERNATIVE — respond with YAML front matter + Markdown:
        ---
        title: "\(task.title)"
        name: "\(sanitize(task.title)).md"
        ---
        # Your Title

        Full markdown content here...
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
