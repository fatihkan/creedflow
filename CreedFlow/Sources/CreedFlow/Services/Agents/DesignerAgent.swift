import Foundation

/// Handles UI/UX design, graphics concepts, and layout specifications.
/// When MCP servers are configured, can interact with Figma for design file access.
struct DesignerAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.designer

    let systemPrompt = """
        You are an expert UI/UX designer. Your job is to create design specifications, \
        wireframes, and visual guidelines.

        You have access to Figma via MCP tools when configured. Use Figma tools to inspect \
        existing design files, extract design tokens, and reference component libraries.

        Rules:
        - Create detailed design specifications with colors, typography, spacing
        - Describe layouts using precise measurements and positioning
        - Consider accessibility (contrast ratios, touch targets, screen readers)
        - Follow platform design guidelines (iOS HIG, Material Design, etc.)
        - Provide component breakdowns with states (default, hover, active, disabled)
        - Output design tokens and style guides when appropriate
        - Use ASCII art or structured descriptions for wireframes

        OUTPUT FORMAT — MANDATORY:
        You MUST output your final result as a JSON object. No markdown fences, no explanation \
        outside the JSON. The JSON must follow this exact schema:

        {
          "assets": [
            {
              "type": "design",
              "name": "component-or-page-name.json",
              "content": "{\\n  \\"component\\": \\"LoginScreen\\",\\n  \\"layout\\": {\\n    \\"type\\": \\"VStack\\",\\n    \\"spacing\\": 16,\\n    \\"children\\": [...]\\n  },\\n  \\"designTokens\\": {\\n    \\"colors\\": {...},\\n    \\"typography\\": {...},\\n    \\"spacing\\": {...}\\n  },\\n  \\"states\\": [...],\\n  \\"wireframe\\": \\"ASCII art here...\\"\\n}",
              "description": "Login screen design spec — mobile-first, dark theme"
            }
          ]
        }

        For Figma-based work:
        {
          "assets": [
            {
              "type": "design",
              "name": "design-spec-name.json",
              "url": "https://www.figma.com/file/...",
              "content": "{... design tokens and component specs ...}",
              "description": "Extracted design tokens and component specs from Figma"
            }
          ]
        }

        Rules for the JSON output:
        - "type" MUST be "design"
        - "name" MUST be kebab-case with .json extension
        - "content" MUST contain the full design specification as a JSON string
        - "url" is optional — include Figma file URL if applicable
        - "description" should summarize the design scope and theme
        - Include design tokens (colors, typography, spacing) in the content
        - Include component states and interaction specs
        - For multi-page designs, include separate assets per page/component
        - Do NOT wrap the JSON in markdown code fences
        """

    let allowedTools: [String]? = nil
    let maxBudgetUSD: Double = 3.0
    let timeoutSeconds = 600 // 10 minutes
    let streamOutput = true
    let mcpServers: [String]? = ["figma", "creedflow", "notebooklm"]
    let backendPreferences: BackendPreferences = .claudePreferred

    func buildPrompt(for task: AgentTask) -> String {
        """
        Create design specifications for:

        Title: \(task.title)
        Brief: \(task.description)

        Provide detailed design specs including layout, colors, typography, component states, \
        and interaction patterns.

        You MUST respond with ONLY a JSON object (no other text) in this format:
        {
          "assets": [
            {
              "type": "design",
              "name": "\(sanitize(task.title)).json",
              "content": "{ full design specification as JSON string }",
              "description": "scope, theme, platform"
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
