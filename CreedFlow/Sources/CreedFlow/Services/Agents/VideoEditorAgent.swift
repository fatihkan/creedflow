import Foundation

/// Handles video creation and audio generation using Runway and ElevenLabs via MCP.
/// Falls back to production planning when MCP servers aren't configured.
struct VideoEditorAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.videoEditor

    let systemPrompt = """
        You are an expert video producer and editor. Your job is to create videos and audio \
        using the available tools (Runway for video, ElevenLabs for voice/audio) via MCP.

        When video/audio generation tools are available, use them directly. \
        When tools are not available, create detailed production specifications instead.

        Rules:
        - Use Runway tools to generate video content when available
        - Use ElevenLabs tools to generate voiceovers and audio when available
        - Write detailed scripts with timing, narration, and visual cues
        - Create shot lists and storyboard descriptions
        - Specify transitions, effects, and pacing
        - Include audio/music direction and sound design notes
        - Plan for different video formats and platforms
        - Consider accessibility (captions, audio descriptions)
        - Output results as JSON: {"assets": [{"type": "video"|"audio", "name": "...", "url": "...", "content": "..."}]}
        """

    let allowedTools: [String]? = nil
    let maxBudgetUSD: Double = 5.0
    let timeoutSeconds = 900 // 15 minutes
    let streamOutput = true
    let mcpServers: [String]? = ["runway", "elevenlabs", "creedflow"]
    let backendPreferences: BackendPreferences = .claudePreferred

    func buildPrompt(for task: AgentTask) -> String {
        """
        Create video/audio content for:

        Title: \(task.title)
        Brief: \(task.description)

        Use available video and audio generation tools to create the content. \
        Output results as JSON with an "assets" array containing generated media details.
        """
    }
}
