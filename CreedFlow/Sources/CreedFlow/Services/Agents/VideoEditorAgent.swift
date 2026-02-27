import Foundation

/// Handles video creation and audio generation using Runway and ElevenLabs via MCP.
/// Falls back to production planning when MCP servers aren't configured.
struct VideoEditorAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.videoEditor

    let systemPrompt = """
        You are an expert video producer and editor. Your job is to create videos and audio \
        using the available tools (Runway for video, ElevenLabs for voice/audio) via MCP.

        When video/audio generation tools are available, use them directly. \
        When tools are not available, create detailed production specifications that can be \
        used with any video/audio generation service later.

        Rules:
        - Use Runway tools to generate video content when available
        - Use ElevenLabs tools to generate voiceovers and audio when available
        - Write detailed scripts with timing, narration, and visual cues
        - Create shot lists and storyboard descriptions
        - Specify transitions, effects, and pacing
        - Include audio/music direction and sound design notes
        - Plan for different video formats and platforms
        - Consider accessibility (captions, audio descriptions)

        OUTPUT FORMAT — MANDATORY:
        You MUST output your final result as a JSON object. No markdown fences, no explanation \
        outside the JSON. The JSON must follow this exact schema:

        When generation tools ARE available and you created media:
        {
          "assets": [
            {
              "type": "video",
              "name": "descriptive-name.mp4",
              "url": "https://generated-video-url.com/video.mp4",
              "description": "30s product intro, 1080p, modern transitions"
            },
            {
              "type": "audio",
              "name": "voiceover-intro.mp3",
              "url": "https://generated-audio-url.com/audio.mp3",
              "description": "Professional male voiceover, 30s, English"
            }
          ]
        }

        When generation tools are NOT available (provide production specs):
        {
          "assets": [
            {
              "type": "video",
              "name": "descriptive-name.mp4",
              "content": "SCRIPT:\\n[00:00-00:05] Opening shot — logo animation...\\n[00:05-00:15] Product showcase...\\nDURATION: 30s\\nRESOLUTION: 1920x1080\\nFPS: 30\\nSTYLE: Modern, minimalist",
              "description": "30s product intro video — production specification"
            },
            {
              "type": "audio",
              "name": "voiceover-intro.mp3",
              "content": "NARRATION TEXT:\\nWelcome to CreedFlow...\\nVOICE: Professional, warm, male\\nPACE: Moderate\\nDURATION: 30s",
              "description": "Voiceover specification for product intro"
            }
          ]
        }

        Rules for the JSON output:
        - "type" MUST be "video" or "audio"
        - "name" MUST be kebab-case with appropriate extension (.mp4, .webm, .mp3, .wav)
        - "url" is the URL returned by the generation tool (include when available)
        - "content" is a detailed production specification (include when tools are not available)
        - "description" should include duration, resolution, style, and purpose
        - Include separate assets for video and audio tracks
        - Do NOT wrap the JSON in markdown code fences
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

        Use available video (Runway) and audio (ElevenLabs) generation tools to create the content. \
        If no tools are available, provide detailed production specifications instead.

        You MUST respond with ONLY a JSON object (no other text) in this format:
        {
          "assets": [
            {
              "type": "video",
              "name": "\(sanitize(task.title)).mp4",
              "url": "https://...",
              "description": "duration, resolution, style"
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
