import Foundation

/// Creates detailed project plans, sprint breakdowns, timelines, milestones,
/// dependency graphs, risk analyses, and roadmaps.
/// Operates in 3 modes based on task description prefix:
/// - Default: Task planning with step-by-step breakdown
/// - [SPRINT]: Sprint planning with story points and capacity
/// - [ROADMAP]: Long-term project roadmap with phases and risk analysis
struct PlannerAgent: AgentProtocol {
    let agentType = AgentTask.AgentType.planner

    let systemPrompt = """
        You are a senior project planner and strategist. \
        You create detailed project plans, sprint breakdowns, timelines, milestones, \
        dependency graphs, risk analyses, and roadmaps. \
        You focus on actionable planning — not code architecture or technical analysis. \
        Your output is structured markdown with clear phases, deliverables, and timelines.
        """

    let allowedTools: [String]? = nil
    let maxBudgetUSD: Double = 1.0
    let timeoutSeconds = 300
    let streamOutput = true
    let mcpServers: [String]? = nil
    let backendPreferences: BackendPreferences = .anyBackend

    func buildPrompt(for task: AgentTask) -> String {
        let desc = task.description

        if desc.contains("[SPRINT]") {
            let clean = desc.replacingOccurrences(of: "[SPRINT]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            Create a SPRINT PLAN for the following project/feature.

            Include:
            - Sprint goals and scope
            - Task breakdown with story points or estimated hours
            - Task prioritization (P0/P1/P2)
            - Sprint capacity and velocity assumptions
            - Dependencies between tasks
            - Acceptance criteria for sprint completion
            - Risk factors and mitigation

            Format as structured markdown with tables where appropriate.

            Title: \(task.title)

            Description: \(clean)
            """
        } else if desc.contains("[ROADMAP]") {
            let clean = desc.replacingOccurrences(of: "[ROADMAP]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            Create a PROJECT ROADMAP for the following project.

            Include:
            - Executive summary
            - Project phases with timelines (Phase 1, 2, 3...)
            - Key milestones and deliverables per phase
            - Resource requirements and team allocation
            - Risk analysis with probability and impact
            - Alternative approaches and trade-offs
            - Success metrics and KPIs
            - Dependencies and critical path

            Format as structured markdown with Mermaid Gantt chart if applicable.

            Title: \(task.title)

            Description: \(clean)
            """
        } else {
            return """
            Create a detailed TASK PLAN for the following work.

            Include:
            - Objective and scope
            - Step-by-step task breakdown
            - Dependencies and ordering (DAG)
            - Timeline with milestones
            - Estimated complexity per task (low/medium/high)
            - Risks and blockers
            - Definition of done

            Format as structured markdown.

            Title: \(task.title)

            Description: \(desc)
            """
        }
    }
}
