import Foundation

/// Parses project descriptions into structured task lists with dependency graphs.
struct AnalyzerAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.analyzer

    let systemPrompt = """
        You are an expert software architect. Your job is to analyze a project description \
        and decompose it into features and implementation tasks.

        For each task, specify:
        - A clear, atomic title
        - Detailed description of what needs to be implemented
        - Priority (1-10, where 10 is highest)
        - Agent type needed (coder, devops, tester)
        - Dependencies on other tasks (by title reference)

        Output MUST be valid JSON matching the provided schema.
        Think step by step about the dependency graph — no circular dependencies allowed.
        Order tasks so that foundational work (database schema, models, configuration) comes first, \
        followed by business logic, then UI, then tests.
        """

    let allowedTools: [String]? = ["Read", "Glob", "Grep"]
    let maxBudgetUSD: Double = 2.0
    let timeoutSeconds = 300 // 5 minutes
    let streamOutput = false

    var jsonSchema: String? {
        """
        {
          "type": "object",
          "properties": {
            "projectName": { "type": "string" },
            "techStack": { "type": "string" },
            "features": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "name": { "type": "string" },
                  "description": { "type": "string" },
                  "priority": { "type": "integer" },
                  "tasks": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "title": { "type": "string" },
                        "description": { "type": "string" },
                        "agentType": { "type": "string", "enum": ["coder", "devops", "tester"] },
                        "priority": { "type": "integer" },
                        "dependsOn": { "type": "array", "items": { "type": "string" } }
                      },
                      "required": ["title", "description", "agentType", "priority"]
                    }
                  }
                },
                "required": ["name", "description", "priority", "tasks"]
              }
            }
          },
          "required": ["projectName", "techStack", "features"]
        }
        """
    }

    func buildPrompt(for task: AgentTask) -> String {
        """
        Analyze the following project description and create a detailed feature/task breakdown:

        \(task.description)

        Read any existing files in the project directory for additional context.
        """
    }
}
