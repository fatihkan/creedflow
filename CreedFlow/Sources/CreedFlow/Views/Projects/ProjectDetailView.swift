import SwiftUI
import GRDB

struct ProjectDetailView: View {
    let projectId: UUID
    let appDatabase: AppDatabase?
    let orchestrator: Orchestrator?
    var onViewAllTasks: (() -> Void)?

    @State private var project: Project?
    @State private var tasks: [AgentTask] = []
    @State private var features: [Feature] = []
    @State private var showAnalyze = false
    @State private var showRevisionSheet = false
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
                            Label(analyzerRunning ? "Analysis Running..." : "Analyze Project", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.forgeAmber)
                        .disabled(analyzerRunning)

                        if !features.isEmpty {
                            Button {
                                showRevisionSheet = true
                            } label: {
                                Label("Add Features", systemImage: "plus.rectangle.on.rectangle")
                            }
                            .buttonStyle(.bordered)
                            .tint(.forgeInfo)
                            .disabled(analyzerRunning)
                        }

                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: project.directoryPath))
                        } label: {
                            Label("Finder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!FileManager.default.fileExists(atPath: project.directoryPath))

                        Button {
                            openTerminal(at: project.directoryPath)
                        } label: {
                            Label("Terminal", systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!FileManager.default.fileExists(atPath: project.directoryPath))
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
                                Button {
                                    onViewAllTasks?()
                                } label: {
                                    Text("View all \(tasks.count) tasks →")
                                        .font(.caption)
                                        .foregroundStyle(.forgeAmber)
                                }
                                .buttonStyle(.plain)
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
        .sheet(isPresented: $showRevisionSheet) {
            if let project {
                ProjectRevisionSheet(
                    project: project,
                    features: features,
                    appDatabase: appDatabase,
                    orchestrator: orchestrator
                )
            }
        }
    }

    private var analyzerRunning: Bool {
        tasks.contains { $0.agentType == .analyzer && ($0.status == .queued || $0.status == .inProgress) }
    }

    private func observeData() async {
        guard let db = appDatabase else { return }
        // Observe project + tasks + features together
        let observation = ValueObservation.tracking { db -> (Project?, [AgentTask], [Feature]) in
            let project = try Project.fetchOne(db, id: projectId)
            let tasks = try AgentTask
                .filter(Column("projectId") == projectId)
                .order(Column("priority").desc, Column("createdAt").asc)
                .fetchAll(db)
            let features = try Feature
                .filter(Column("projectId") == projectId)
                .order(Column("priority").desc, Column("name").asc)
                .fetchAll(db)
            return (project, tasks, features)
        }
        do {
            for try await (proj, taskList, featureList) in observation.values(in: db.dbQueue) {
                project = proj
                tasks = taskList
                features = featureList
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
