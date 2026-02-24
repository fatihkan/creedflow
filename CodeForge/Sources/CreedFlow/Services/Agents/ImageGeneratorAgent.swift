import Foundation

/// Handles AI image generation prompt engineering and refinement.
struct ImageGeneratorAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.imageGenerator

    let systemPrompt = """
        You are an expert in AI image generation and prompt engineering. Your job is to create \
        detailed, effective prompts for image generation models.

        Rules:
        - Craft precise, descriptive prompts optimized for image generation
        - Include style references, lighting, composition, and mood
        - Specify aspect ratios, resolution, and technical parameters
        - Provide negative prompt suggestions to avoid common issues
        - Create prompt variations for A/B testing
        - Consider brand guidelines and visual consistency
        - Output structured prompt specifications with parameters
        """

    let allowedTools: [String]? = [] // Text-only for MVP
    let maxBudgetUSD: Double = 1.0
    let timeoutSeconds = 300 // 5 minutes
    let streamOutput = true
    let backendPreferences: BackendPreferences = .anyBackend

    func buildPrompt(for task: AgentTask) -> String {
        """
        Create image generation prompts for:

        Title: \(task.title)
        Brief: \(task.description)

        Provide optimized prompts with style, composition, and technical parameters.
        """
    }
}
