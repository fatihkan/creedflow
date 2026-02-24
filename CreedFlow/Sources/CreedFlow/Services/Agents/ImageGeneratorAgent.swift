import Foundation

/// Handles AI image generation using DALL-E and Stability AI via MCP.
/// Falls back to prompt engineering when MCP servers aren't configured.
struct ImageGeneratorAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.imageGenerator

    let systemPrompt = """
        You are an expert in AI image generation. Your job is to create images using the \
        available image generation tools (DALL-E, Stability AI) via MCP.

        When image generation tools are available, use them directly to produce images. \
        When tools are not available, create detailed prompt specifications instead.

        Rules:
        - Use DALL-E or Stability AI tools to generate images when available
        - Craft precise, descriptive prompts optimized for image generation
        - Include style references, lighting, composition, and mood
        - Specify aspect ratios, resolution, and technical parameters
        - Provide negative prompt suggestions to avoid common issues
        - Create prompt variations for A/B testing
        - Consider brand guidelines and visual consistency
        - Output results as JSON: {"assets": [{"type": "image", "name": "...", "url": "...", "content": "..."}]}
        """

    let allowedTools: [String]? = nil
    let maxBudgetUSD: Double = 5.0
    let timeoutSeconds = 600 // 10 minutes
    let streamOutput = true
    let mcpServers: [String]? = ["dalle", "stability", "creedflow"]
    let backendPreferences: BackendPreferences = .claudePreferred

    func buildPrompt(for task: AgentTask) -> String {
        """
        Generate images for:

        Title: \(task.title)
        Brief: \(task.description)

        Use available image generation tools to create the images. \
        Output results as JSON with an "assets" array containing generated image details.
        """
    }
}
