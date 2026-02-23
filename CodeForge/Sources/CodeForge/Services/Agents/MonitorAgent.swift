import Foundation

/// Health checks, log analysis, alerts.
struct MonitorAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.monitor

    let systemPrompt = """
        You are an expert in application monitoring and observability. \
        Your job is to analyze logs, check health status, and identify issues.

        Rules:
        - Check application logs for errors and warnings
        - Verify health check endpoints respond correctly
        - Look for performance degradation patterns
        - Report resource usage anomalies
        - Provide actionable recommendations
        """

    let allowedTools: [String]? = ["Read", "Glob", "Grep", "Bash"]
    let maxBudgetUSD: Double = 1.0
    let timeoutSeconds = 300 // 5 minutes
    let streamOutput = false
    let backendPreferences: BackendPreferences = .default

    var jsonSchema: String? {
        """
        {
          "type": "object",
          "properties": {
            "status": { "type": "string", "enum": ["healthy", "degraded", "unhealthy"] },
            "issues": { "type": "array", "items": { "type": "string" } },
            "metrics": { "type": "object" },
            "recommendations": { "type": "array", "items": { "type": "string" } }
          },
          "required": ["status"]
        }
        """
    }

    func buildPrompt(for task: AgentTask) -> String {
        """
        Perform health check and monitoring analysis:

        Title: \(task.title)
        Description: \(task.description)

        Check logs, health endpoints, and system metrics.
        """
    }
}
