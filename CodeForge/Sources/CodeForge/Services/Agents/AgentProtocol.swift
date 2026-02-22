import Foundation

/// Protocol that all agent types conform to.
/// Defines the configuration for how a Claude CLI session should be spawned.
protocol AgentProtocol: Sendable {
    var agentType: AgentTask.AgentType { get }
    var systemPrompt: String { get }
    var allowedTools: [String]? { get }
    var maxBudgetUSD: Double { get }
    var timeoutSeconds: Int { get }
    var jsonSchema: String? { get }
    var streamOutput: Bool { get }

    /// Build a prompt for the given task
    func buildPrompt(for task: AgentTask) -> String

    /// Build a full ClaudeInvocation from a task
    func buildInvocation(for task: AgentTask) -> ClaudeInvocation
}

extension AgentProtocol {
    var jsonSchema: String? { nil }
    var streamOutput: Bool { true }

    func buildInvocation(for task: AgentTask) -> ClaudeInvocation {
        ClaudeInvocation(
            prompt: buildPrompt(for: task),
            workingDirectory: "", // Set by orchestrator based on project directory
            systemPrompt: systemPrompt,
            outputFormat: streamOutput ? .streamJSON : .json,
            allowedTools: allowedTools,
            maxBudgetUSD: maxBudgetUSD,
            jsonSchema: jsonSchema
        )
    }
}
