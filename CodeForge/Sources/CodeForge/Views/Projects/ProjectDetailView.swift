import SwiftUI
import GRDB

struct ProjectDetailView: View {
    let projectId: UUID
    let appDatabase: AppDatabase?
    let orchestrator: Orchestrator?

    @State private var project: Project?
    @State private var tasks: [AgentTask] = []
    @State private var showAnalyze = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if let project {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.title2.bold())
                            Text(project.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            if !project.techStack.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "wrench.and.screwdriver")
                                    Text(project.techStack)
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text(project.status.displayName)
                            .forgeBadge(color: project.status.themeColor)
                    }

                    // Stats row
                    HStack(spacing: 12) {
                        MetricCard(
                            label: "Total",
                            value: "\(tasks.count)",
                            icon: "checklist",
                            accent: .forgeAmber
                        )
                        MetricCard(
                            label: "Done",
                            value: "\(tasks.filter { $0.status == .passed }.count)",
                            icon: "checkmark.circle",
                            accent: .forgeSuccess
                        )
                        MetricCard(
                            label: "Active",
                            value: "\(tasks.filter { $0.status == .inProgress }.count)",
                            icon: "play.circle",
                            accent: .forgeInfo
                        )
                        MetricCard(
                            label: "Failed",
                            value: "\(tasks.filter { $0.status == .failed }.count)",
                            icon: "xmark.circle",
                            accent: .forgeDanger
                        )
                    }

                    if let errorMessage {
                        ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                    }

                    // Actions
                    HStack(spacing: 8) {
                        Button {
                            showAnalyze = true
                        } label: {
                            Label("Analyze Project", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.forgeAmber)

                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: project.directoryPath))
                        } label: {
                            Label("Finder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            openTerminal(at: project.directoryPath)
                        } label: {
                            Label("Terminal", systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                    }

                    // Recent tasks
                    if !tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Recent Tasks")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            ForEach(tasks.prefix(8)) { task in
                                TaskRowCompactView(task: task)
                            }
                            if tasks.count > 8 {
                                Text("\(tasks.count - 8) more...")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(16)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: projectId) {
            await observeData()
        }
        .alert("Analyze Project", isPresented: $showAnalyze) {
            Button("Start Analysis") {
                Task { await startAnalysis() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will use Claude to analyze the project and create a task breakdown.")
        }
    }

    private func observeData() async {
        guard let db = appDatabase else { return }
        // Observe project + tasks together
        let observation = ValueObservation.tracking { db -> (Project?, [AgentTask]) in
            let project = try Project.fetchOne(db, id: projectId)
            let tasks = try AgentTask
                .filter(Column("projectId") == projectId)
                .order(Column("priority").desc, Column("createdAt").asc)
                .fetchAll(db)
            return (project, tasks)
        }
        do {
            for try await (proj, taskList) in observation.values(in: db.dbQueue) {
                project = proj
                tasks = taskList
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAnalysis() async {
        guard let db = appDatabase, let project else { return }
        do {
            try await db.dbQueue.write { dbConn in
                var newTask = AgentTask(
                    projectId: project.id,
                    agentType: .analyzer,
                    title: "Analyze: \(project.name)",
                    description: project.description,
                    priority: 10
                )
                try newTask.insert(dbConn)
            }
            if let orchestrator, !orchestrator.isRunning {
                await orchestrator.start()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openTerminal(at path: String) {
        let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"cd \\\"\(escapedPath)\\\"\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

}

// MARK: - Metric Card

struct MetricCard: View {
    let label: String
    let value: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .forgeMetricCard(accent: accent)
    }
}
