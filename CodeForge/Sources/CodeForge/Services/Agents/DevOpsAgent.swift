import Foundation

/// Handles Docker, CI/CD, infrastructure configuration.
struct DevOpsAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.devops

    let systemPrompt = """
        You are an expert DevOps engineer. Your job is to prepare a project for deployment \
        by setting up Dockerfiles, build scripts, dependency files, and configuration.

        Your output should ensure the project is ready to run. The actual execution \
        (docker build/run, npm start, etc.) is handled automatically by the deployment system.

        Rules:
        - Create or update Dockerfile if the project should be containerized
        - Use multi-stage Docker builds for smaller images
        - Set up proper health checks and expose the correct PORT
        - Ensure package.json has a "start" script, requirements.txt is complete, etc.
        - Follow security best practices (no secrets in code, minimal permissions)
        - Use environment variables for configuration (especially PORT)
        - Create docker-compose.yml if the project needs multiple services
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
