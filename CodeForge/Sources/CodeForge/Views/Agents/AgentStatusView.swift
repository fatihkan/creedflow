import SwiftUI
import GRDB

struct AgentStatusView: View {
    let orchestrator: Orchestrator?
    @Binding var selectedTaskId: UUID?
    let appDatabase: AppDatabase?
    var onNavigateToTasks: (() -> Void)?

    @State private var taskMap: [UUID: AgentTask] = [:]
    @State private var projects: [Project] = []
    @State private var selectedProjectForHealth: UUID?
    @State private var healthCheckTriggered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let orchestrator {
                // Orchestrator status header
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(orchestrator.isRunning ? Color.forgeSuccess : Color.forgeDanger)
                            .frame(width: 8, height: 8)
                            .overlay {
                                if orchestrator.isRunning {
                                    Circle()
                                        .fill(Color.forgeSuccess.opacity(0.3))
                                        .frame(width: 16, height: 16)
                                }
                            }
                        Text(orchestrator.isRunning ? "Orchestrator Running" : "Orchestrator Stopped")
                            .font(.system(.subheadline, weight: .semibold))
                    }

                    Spacer()

                    if orchestrator.isRunning {
                        Text("\(orchestrator.activeRunners.count) active")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.quaternary.opacity(0.3))

                // Active runners
                if orchestrator.activeRunners.isEmpty {
                    ForgeEmptyState(
                        icon: "cpu",
                        title: "No Active Agents",
                        subtitle: "Agents will appear here when tasks are being processed",
                        actionTitle: "View Tasks",
                        action: onNavigateToTasks
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(orchestrator.activeRunners.keys), id: \.self) { taskId in
                                if let runner = orchestrator.activeRunners[taskId] {
                                    activeRunnerCard(taskId: taskId, runner: runner)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            } else {
                ForgeEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Not Initialized",
                    subtitle: "The orchestrator needs a database connection"
                )
            }
        }
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Picker("Project", selection: $selectedProjectForHealth) {
                        Text("Select project").tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    .frame(maxWidth: 180)

                    Button {
                        triggerHealthCheck()
                    } label: {
                        Label(
                            healthCheckTriggered ? "Queued" : "Health Check",
                            systemImage: healthCheckTriggered ? "checkmark.circle" : "heart.text.square"
                        )
                    }
                    .disabled(selectedProjectForHealth == nil || healthCheckTriggered)
                }
            }
        }
        .task {
            await observeActiveTasks()
        }
        .task {
            await observeProjects()
        }
    }

    private func activeRunnerCard(taskId: UUID, runner: ClaudeAgentRunner) -> some View {
        let task = taskMap[taskId]

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let task {
                    AgentTypeBadge(type: task.agentType)
                    Text(task.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(1)
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Task \(taskId.uuidString.prefix(8))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                Spacer()
                Text("\(runner.liveOutput.count) lines")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Last output line preview
            if let lastLine = runner.liveOutput.last {
                Text(lastLine.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.forgeTerminalBg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Mini terminal toggle
            Button {
                selectedTaskId = taskId
            } label: {
                Text("View Full Console")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.forgeAmber)
        }
        .padding(12)
        .forgeCard(cornerRadius: 8)
    }

    private func triggerHealthCheck() {
        guard let db = appDatabase, let projectId = selectedProjectForHealth else { return }
        try? db.dbQueue.write { dbConn in
            var task = AgentTask(
                projectId: projectId,
                agentType: .monitor,
                title: "Health Check",
                description: "Run a health check on the project: verify services, check logs for errors, and report status.",
                priority: 5
            )
            try task.insert(dbConn)
        }
        healthCheckTriggered = true
        // Reset after 3 seconds
        Task {
            try? await Task.sleep(for: .seconds(3))
            healthCheckTriggered = false
        }
    }

    private func observeProjects() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try Project.order(Column("name").asc).fetchAll(db)
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                projects = value
            }
        } catch {}
    }

    private func observeActiveTasks() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try AgentTask
                .filter(Column("status") == AgentTask.Status.inProgress.rawValue)
                .fetchAll(db)
        }
        do {
            for try await tasks in observation.values(in: db.dbQueue) {
                var map: [UUID: AgentTask] = [:]
                for t in tasks { map[t.id] = t }
                taskMap = map
            }
        } catch {}
    }
}
