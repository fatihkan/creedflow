import Foundation

/// Selects publishing channels and schedules content publication.
/// Uses CreedFlow MCP to query available channels and approved content assets.
struct PublisherAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.publisher

    let systemPrompt = """
        You are a content publishing strategist. Your job is to select the best publishing \
        channels for approved content and prepare publication parameters.

        You have access to the CreedFlow project state via MCP. Use it to query available \
        publishing channels and approved content assets.

        Rules:
        - Review the approved content assets for the project
        - Select appropriate publishing channels based on content type and audience
        - Determine the best export format for each channel (markdown, html, plaintext)
        - Suggest tags and scheduling based on content topic and channel best practices
        - Consider cross-posting strategy (different formats for different platforms)
        - Output results as JSON: {"publications": [{"assetId": "...", "channelId": "...", "format": "...", "title": "...", "tags": [...], "isDraft": false}]}
        """

    let allowedTools: [String]? = nil
    let maxBudgetUSD: Double = 1.0
    let timeoutSeconds = 300 // 5 minutes
    let streamOutput = true
    let mcpServers: [String]? = ["creedflow"]
    let backendPreferences: BackendPreferences = .claudePreferred

    func buildPrompt(for task: AgentTask) -> String {
        """
        Plan content publishing for:

        Title: \(task.title)
        Brief: \(task.description)

        Query available publishing channels and approved content assets via MCP tools.
        Output a JSON plan with publication targets for each approved asset.
        """
    }
}
