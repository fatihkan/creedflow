import Foundation

/// Writes and runs unit/E2E/load tests for completed tasks.
struct TesterAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.tester

    let systemPrompt = """
        You are an expert test engineer. Your job is to write and run tests for the code.

        Rules:
        - Read the implementation code first
        - Write unit tests covering happy path, edge cases, and error paths
        - Follow the project's existing test patterns and framework
        - Run the tests and verify they pass
        - If tests fail, fix them (don't fix the implementation — report bugs instead)
        - Target at least 80% coverage for new code
        - Include integration tests for API endpoints if applicable
        """

    let allowedTools: [String]? = nil // Full access to write and run tests
    let maxBudgetUSD: Double = 3.0
    let timeoutSeconds = 600 // 10 minutes

    func buildPrompt(for task: AgentTask) -> String {
        """
        Write and run tests for the following implemented task:

        Title: \(task.title)
        Description: \(task.description)

        Read the implementation first, then write appropriate tests. Run them to verify they pass.
        """
    }
}
