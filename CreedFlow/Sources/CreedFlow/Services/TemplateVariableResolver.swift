import Foundation

struct TemplateVariableResolver {
    /// Extract all `{{variable_name}}` patterns from a template string.
    static func extractVariables(from template: String) -> [String] {
        let pattern = "\\{\\{\\s*([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(template.startIndex..., in: template)
        let matches = regex.matches(in: template, range: range)
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            if let r = Range(match.range(at: 1), in: template) {
                let name = String(template[r])
                if seen.insert(name).inserted {
                    result.append(name)
                }
            }
        }
        return result
    }

    /// Built-in variable names that can be auto-filled from project/task context.
    static let builtInVariables: Set<String> = [
        "project_name", "tech_stack", "project_type", "date",
        "task_title", "task_description", "agent_type",
        "error_message", "previous_output", "retry_count",
        "chain_step", "chain_total_steps"
    ]

    /// Resolve built-in variables from a project context.
    static func builtInValues(projectName: String?, techStack: String?, projectType: String?) -> [String: String] {
        var values: [String: String] = [:]
        if let name = projectName, !name.isEmpty {
            values["project_name"] = name
        }
        if let stack = techStack, !stack.isEmpty {
            values["tech_stack"] = stack
        }
        if let type = projectType, !type.isEmpty {
            values["project_type"] = type
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        values["date"] = formatter.string(from: Date())
        return values
    }

    /// Resolve task-level variables from a task and optional previous output.
    static func taskContextValues(task: AgentTask, previousOutput: String? = nil) -> [String: String] {
        var values: [String: String] = [:]
        values["task_title"] = task.title
        values["task_description"] = task.description
        values["agent_type"] = task.agentType.rawValue
        values["retry_count"] = String(task.retryCount)
        if let error = task.errorMessage, !error.isEmpty {
            values["error_message"] = error
        }
        if let output = previousOutput, !output.isEmpty {
            values["previous_output"] = output
        }
        return values
    }

    /// Combine project + task context into a single values dictionary.
    static func allValues(
        projectName: String?,
        techStack: String?,
        projectType: String?,
        task: AgentTask,
        previousOutput: String? = nil
    ) -> [String: String] {
        var values = builtInValues(projectName: projectName, techStack: techStack, projectType: projectType)
        let taskValues = taskContextValues(task: task, previousOutput: previousOutput)
        values.merge(taskValues) { _, new in new }
        return values
    }

    /// Replace all `{{variable_name}}` occurrences with provided values.
    /// Variables without a value are left as-is.
    static func resolve(template: String, values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            let pattern = "\\{\\{\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*\\}\\}"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: value))
            }
        }
        return result
    }
}
