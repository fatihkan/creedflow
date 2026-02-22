import Foundation

/// Handles Docker, CI/CD, infrastructure configuration.
struct DevOpsAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.devops

    let systemPrompt = """
        You are an expert DevOps engineer. Your job is to set up infrastructure, \
        CI/CD pipelines, Docker configuration, and deployment scripts.

        Rules:
        - Follow security best practices (no secrets in code, minimal permissions)
        - Use multi-stage Docker builds for smaller images
        - Set up proper health checks
        - Configure CI to run tests before allowing merge
        - Use environment variables for configuration
        """

    let allowedTools: [String]? = nil
    let maxBudgetUSD: Double = 3.0
    let timeoutSeconds = 600 // 10 minutes

    func buildPrompt(for task: AgentTask) -> String {
        """
        Set up infrastructure/DevOps for:

        Title: \(task.title)
        Description: \(task.description)

        Read existing project structure and configuration before making changes.
        """
    }
}
