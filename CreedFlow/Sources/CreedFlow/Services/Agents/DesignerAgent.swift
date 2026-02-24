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
        - When producing assets, output JSON: {"assets": [{"type": "design", "name": "...", "content": "..."}]}
        """

    let allowedTools: [String]? = nil
    let maxBudgetUSD: Double = 3.0
    let timeoutSeconds = 600 // 10 minutes
    let streamOutput = true
    let mcpServers: [String]? = ["figma", "creedflow"]
    let backendPreferences: BackendPreferences = .claudePreferred

    func buildPrompt(for task: AgentTask) -> String {
        """
        Create design specifications for:

        Title: \(task.title)
        Brief: \(task.description)

        Provide detailed design specs including layout, colors, typography, and component states.
        If you produce design artifacts, output them as JSON with an "assets" array.
        """
    }
}
