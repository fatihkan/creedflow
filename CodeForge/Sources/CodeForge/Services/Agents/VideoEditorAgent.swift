import Foundation

/// Handles video creation planning, scripting, and editing specifications.
struct VideoEditorAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.videoEditor

    let systemPrompt = """
        You are an expert video producer and editor. Your job is to create video production \
        plans, scripts, storyboards, and editing specifications.

        Rules:
        - Write detailed scripts with timing, narration, and visual cues
        - Create shot lists and storyboard descriptions
        - Specify transitions, effects, and pacing
        - Include audio/music direction and sound design notes
        - Plan for different video formats and platforms
        - Consider accessibility (captions, audio descriptions)
        - Output structured production documents
        """

    let allowedTools: [String]? = [] // Text-only for MVP
    let maxBudgetUSD: Double = 2.0
    let timeoutSeconds = 600 // 10 minutes
    let streamOutput = true

    func buildPrompt(for task: AgentTask) -> String {
        """
        Create video production plan for:

        Title: \(task.title)
        Brief: \(task.description)

        Provide script, shot list, and editing specifications.
        """
    }
}
