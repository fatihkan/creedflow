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
    @State private var showExportZip = false
    @State private var errorMessage: String?
    @AppStorage("preferredEditor") private var preferredEditor = ""

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
                                .font(.footnote)
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

                    // Time stats
                    if !tasks.isEmpty {
                        ProjectTimeStatsView(project: project, tasks: tasks)
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

                        if !preferredEditor.isEmpty {
                            Button {
                                openInEditor(at: project.directoryPath)
                            } label: {
                                Label("Editor", systemImage: "chevron.left.forwardslash.chevron.right")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!FileManager.default.fileExists(atPath: project.directoryPath))
                        }

                        Button {
                            showExportZip = true
                        } label: {
                            Label("Export ZIP", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.bordered)
                    }

                    // Recent tasks
                    if !tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Recent Tasks")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            ForEach(tasks.prefix(8), id: \.id) { task in
                                TaskRowCompactView(task: task)
                            }
                            if tasks.count > 8 {
                                Button {
                                    onViewAllTasks?()
                                } label: {
                                    Text("View all \(tasks.count) tasks →")
                                        .font(.footnote)
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
        .onChange(of: showExportZip) { _, show in
            guard show, let project, let db = appDatabase else { return }
            showExportZip = false
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(project.name).zip"
            panel.allowedContentTypes = [.zip]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try ProjectExporter.exportAsZIP(project: project, dbQueue: db.dbQueue, to: url)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
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

    private func openInEditor(at path: String) {
        guard !preferredEditor.isEmpty else { return }
        // Try opening via NSWorkspace using the app's bundle identifier (reliable in .app bundles)
        if let bundleId = Self.editorBundleIds[preferredEditor],
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: path)],
                withApplicationAt: appURL,
                configuration: config
            )
            return
        }
        // Fallback: use CLI command with full environment
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [preferredEditor, path]
        process.environment = ProcessInfo.processInfo.environment
        try? process.run()
    }

    private static let editorBundleIds: [String: String] = [
        "code": "com.microsoft.VSCode",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "zed": "dev.zed.Zed",
        "subl": "com.sublimetext.4",
        "xed": "com.apple.dt.Xcode",
        "windsurf": "com.codeium.windsurf",
    ]

}

// MARK: - Project Time Stats

struct ProjectTimeStatsView: View {
    let project: Project
    let tasks: [AgentTask]

    private var elapsedMs: Int64 {
        let end = project.completedAt ?? Date()
        return Int64(end.timeIntervalSince(project.createdAt) * 1000)
    }

    private var totalWorkMs: Int64 {
        tasks.compactMap(\.durationMs).reduce(0, +)
    }

    private var idleMs: Int64 {
        max(0, elapsedMs - totalWorkMs)
    }

    private var agentBreakdown: [(agentType: String, totalMs: Int64, count: Int)] {
        var grouped: [String: (ms: Int64, count: Int)] = [:]
        for task in tasks {
            let key = task.agentType.rawValue
            let existing = grouped[key] ?? (ms: 0, count: 0)
            grouped[key] = (ms: existing.ms + (task.durationMs ?? 0), count: existing.count + 1)
        }
        return grouped.map { (agentType: $0.key, totalMs: $0.value.ms, count: $0.value.count) }
            .sorted { $0.totalMs > $1.totalMs }
    }

    var body: some View {
        DisclosureGroup("Time Tracking") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    timeStatItem(label: "Elapsed", value: formatDuration(ms: elapsedMs), icon: "clock", color: .forgeInfo)
                    timeStatItem(label: "Work", value: formatDuration(ms: totalWorkMs), icon: "hammer", color: .forgeSuccess)
                    timeStatItem(label: "Idle", value: formatDuration(ms: idleMs), icon: "pause.circle", color: .forgeNeutral)
                }

                if !agentBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Per Agent")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)

                        let maxMs = agentBreakdown.map(\.totalMs).max() ?? 1
                        ForEach(agentBreakdown, id: \.agentType) { item in
                            HStack(spacing: 6) {
                                Text(item.agentType.capitalized)
                                    .font(.system(size: 11))
                                    .frame(width: 80, alignment: .leading)

                                GeometryReader { geo in
                                    let fraction = maxMs > 0 ? CGFloat(item.totalMs) / CGFloat(maxMs) : 0
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.forgeAmber.opacity(0.6))
                                        .frame(width: geo.size.width * fraction)
                                }
                                .frame(height: 8)

                                Text("\(ForgeDuration.format(ms: item.totalMs)) (\(item.count))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .font(.subheadline.bold())
    }

    private func timeStatItem(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formatDuration(ms: Int64) -> String {
        let totalSeconds = Double(ms) / 1000.0
        if totalSeconds < 60 {
            return String(format: "%.0fs", totalSeconds)
        } else if totalSeconds < 3600 {
            let minutes = Int(totalSeconds) / 60
            let seconds = Int(totalSeconds) % 60
            return "\(minutes)m \(seconds)s"
        } else if totalSeconds < 86400 {
            let hours = Int(totalSeconds) / 3600
            let minutes = (Int(totalSeconds) % 3600) / 60
            return "\(hours)h \(minutes)m"
        } else {
            let days = Int(totalSeconds) / 86400
            let hours = (Int(totalSeconds) % 86400) / 3600
            return "\(days)d \(hours)h"
        }
    }
}
