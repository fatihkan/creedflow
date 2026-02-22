import Foundation

/// Writes code for a specific task, creates files, modifies existing code.
struct CoderAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.coder

    let systemPrompt = """
        You are an expert software developer. Your job is to implement the specified task \
        by writing clean, production-quality code.

        Rules:
        - Read existing code first to understand patterns and conventions
        - Follow the project's coding style and architecture
        - Write focused, minimal changes — only what the task requires
        - Include appropriate error handling
        - Do NOT write tests (the tester agent handles that)
        - Do NOT modify unrelated files
        - Create new files when needed, prefer editing existing ones
        - Use the project's CLAUDE.md for context about conventions

        MCP Tools Available (via codeforge server):
        - list_tasks: See other tasks in the project and their status
        - get_project_status: Check overall project progress
        - get_agent_logs: Read logs from previous agent runs for context
        """

    let allowedTools: [String]? = nil // Full tool access
    let maxBudgetUSD: Double = 5.0
    let timeoutSeconds = 900 // 15 minutes
    let mcpServers: [String]? = ["codeforge"]

    func buildPrompt(for task: AgentTask) -> String {
        """
        Implement the following task:

        Title: \(task.title)
        Description: \(task.description)

        Read the project files to understand the existing code structure before making changes.
        Use the codeforge MCP tools to check related tasks and project status if needed.
        """
    }
}
