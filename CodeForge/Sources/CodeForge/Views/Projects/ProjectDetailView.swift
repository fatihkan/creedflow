import SwiftUI
import GRDB

struct ProjectDetailView: View {
    let projectId: UUID
    let appDatabase: AppDatabase?
    let orchestrator: Orchestrator?

    @State private var project: Project?
    @State private var tasks: [AgentTask] = []
    @State private var showAnalyze = false

    var body: some View {
        ScrollView {
            if let project {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(project.name)
                                .font(.largeTitle.bold())
                            Spacer()
                            StatusBadge(status: project.status.rawValue)
                        }
                        Text(project.description)
                            .foregroundStyle(.secondary)
                        if !project.techStack.isEmpty {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver")
                                Text(project.techStack)
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                    }

                    Divider()

                    // Stats
                    HStack(spacing: 24) {
                        StatCard(title: "Tasks", value: "\(tasks.count)", icon: "checklist")
                        StatCard(
                            title: "Completed",
                            value: "\(tasks.filter { $0.status == .passed }.count)",
                            icon: "checkmark.circle"
                        )
                        StatCard(
                            title: "Active",
                            value: "\(tasks.filter { $0.status == .inProgress }.count)",
                            icon: "play.circle"
                        )
                        StatCard(
                            title: "Failed",
                            value: "\(tasks.filter { $0.status == .failed }.count)",
                            icon: "xmark.circle"
                        )
                    }

                    Divider()

                    // Actions
                    HStack {
                        Button("Analyze Project") {
                            showAnalyze = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open in Finder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: project.directoryPath))
                        }

                        Button("Open in Terminal") {
                            openTerminal(at: project.directoryPath)
                        }
                    }

                    // Task list summary
                    if !tasks.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Recent Tasks")
                                .font(.headline)
                            ForEach(tasks.prefix(10)) { task in
                                TaskRowCompactView(task: task)
                            }
                        }
                    }
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .task {
            await loadData()
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

    private func loadData() async {
        guard let db = appDatabase else { return }
        do {
            project = try await db.dbQueue.read { db in
                try Project.fetchOne(db, id: projectId)
            }
            tasks = try await db.dbQueue.read { db in
                try AgentTask
                    .filter(Column("projectId") == projectId)
                    .order(Column("priority").desc, Column("createdAt").asc)
                    .fetchAll(db)
            }
        } catch {}
    }

    private func startAnalysis() async {
        guard let db = appDatabase, let project else { return }

        do {
            try await db.dbQueue.write { dbConn in
                var task = AgentTask(
                    projectId: project.id,
                    agentType: .analyzer,
                    title: "Analyze: \(project.name)",
                    description: project.description,
                    priority: 10
                )
                try task.insert(dbConn)
            }

            // Start orchestrator if not running
            if let orchestrator, !orchestrator.isRunning {
                await orchestrator.start()
            }
        } catch {}
    }

    private func openTerminal(at path: String) {
        let script = "tell application \"Terminal\" to do script \"cd \(path)\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
