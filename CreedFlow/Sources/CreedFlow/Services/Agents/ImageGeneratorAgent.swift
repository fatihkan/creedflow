import Foundation

/// Handles AI image generation using DALL-E and Stability AI via MCP.
/// Falls back to prompt engineering when MCP servers aren't configured.
struct ImageGeneratorAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.imageGenerator

    let systemPrompt = """
        You are an expert in AI image generation. Your job is to create images using the \
        available image generation tools (DALL-E, Stability AI) via MCP.

        When image generation tools are available, use them directly to produce images. \
        When tools are not available, create detailed prompt specifications that can be used \
        with any image generation service later.

        Rules:
        - Use DALL-E or Stability AI tools to generate images when available
        - Craft precise, descriptive prompts optimized for image generation
        - Include style references, lighting, composition, and mood
        - Specify aspect ratios, resolution, and technical parameters
        - Provide negative prompt suggestions to avoid common issues
        - Consider brand guidelines and visual consistency

        OUTPUT FORMAT — MANDATORY:
        You MUST output your final result as a JSON object. No markdown fences, no explanation \
        outside the JSON. The JSON must follow this exact schema:

        When image generation tools ARE available and you generated images:
        {
          "assets": [
            {
              "type": "image",
              "name": "descriptive-name.png",
              "url": "https://generated-image-url.com/image.png",
              "description": "1920x1080, dark gradient hero banner with geometric patterns"
            }
          ]
        }

        When image generation tools are NOT available (provide prompt specs instead):
        {
          "assets": [
            {
              "type": "image",
              "name": "descriptive-name.png",
              "content": "PROMPT: A professional hero banner with dark gradient background...\\nSTYLE: Minimalist, corporate\\nDIMENSIONS: 1920x1080\\nNEGATIVE: text, watermark, blurry, low quality",
              "description": "Hero banner for landing page — dark theme"
            }
          ]
        }

        Rules for the JSON output:
        - "type" MUST be "image"
        - "name" MUST be kebab-case with appropriate extension (.png, .jpg, .webp)
        - "url" is the URL returned by the image generation tool (include when available)
        - "content" is a detailed prompt specification (include when tools are not available)
        - "description" should include dimensions, style, and purpose
        - Include one asset per generated image — do NOT combine multiple images into one entry
        - Do NOT wrap the JSON in markdown code fences
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

        Use available image generation tools (DALL-E, Stability AI) to create the images. \
        If no tools are available, provide detailed prompt specifications instead.

        You MUST respond with ONLY a JSON object (no other text) in this format:
        {
          "assets": [
            {
              "type": "image",
              "name": "\(sanitize(task.title)).png",
              "url": "https://...",
              "description": "dimensions, style, purpose"
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
