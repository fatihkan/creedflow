import Foundation

/// Reviews code changes: AI review + static analysis + security scanning.
/// Read-only access — cannot modify code.
struct ReviewerAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.reviewer

    let systemPrompt = """
        You are an expert code reviewer. Analyze the code changes and provide a thorough review.

        Evaluate on these criteria (each scored 1-10):
        1. Code Quality — readability, naming, structure, DRY
        2. Correctness — logic errors, edge cases, error handling
        3. Security — injection, auth issues, data exposure, OWASP Top 10
        4. Performance — N+1 queries, unnecessary allocations, blocking operations
        5. Architecture — separation of concerns, patterns, coupling

        Scoring:
        - >= 7.0 average: PASS
        - 5.0 - 6.9 average: NEEDS_REVISION (provide specific fix suggestions)
        - < 5.0 average: FAIL (explain critical issues)

        Output must be valid JSON matching the schema.

        MCP Tools Available (via codeforge server):
        - get_agent_logs: Read the coder agent's logs to understand what was done
        - list_tasks: See related tasks for context
        - get_project_status: Check overall project state
        """

    let allowedTools: [String]? = ["Read", "Glob", "Grep", "Bash"]
    let maxBudgetUSD: Double = 2.0
    let timeoutSeconds = 300 // 5 minutes
    let streamOutput = false
    let mcpServers: [String]? = ["codeforge"]

    var jsonSchema: String? {
        """
        {
          "type": "object",
          "properties": {
            "score": { "type": "number" },
            "verdict": { "type": "string", "enum": ["pass", "needs_revision", "fail"] },
            "summary": { "type": "string" },
            "criteria": {
              "type": "object",
              "properties": {
                "codeQuality": { "type": "number" },
                "correctness": { "type": "number" },
                "security": { "type": "number" },
                "performance": { "type": "number" },
                "architecture": { "type": "number" }
              }
            },
            "issues": { "type": "array", "items": { "type": "string" } },
            "suggestions": { "type": "array", "items": { "type": "string" } },
            "securityNotes": { "type": "array", "items": { "type": "string" } }
          },
          "required": ["score", "verdict", "summary"]
        }
        """
    }

    func buildPrompt(for task: AgentTask) -> String {
        let branchInfo = task.branchName.map { "Branch: \($0)" } ?? ""
        return """
        Review the code changes for the following task:

        Title: \(task.title)
        Description: \(task.description)
        \(branchInfo)

        Check the git diff for this branch compared to main. Review all changed files.
        Run any available linters or static analysis tools if present.
        """
    }
}
