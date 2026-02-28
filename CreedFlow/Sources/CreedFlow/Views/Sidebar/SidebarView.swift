import SwiftUI
import GRDB

struct SidebarView: View {
    @Binding var selectedSection: SidebarSection?
    @Binding var selectedProjectId: UUID?
    let orchestrator: Orchestrator?
    let appDatabase: AppDatabase?

    @State private var projects: [Project] = []
    @State private var totalProjectCount: Int = 0
    @State private var activeTaskCount: Int = 0
    @State private var archivedTaskCount: Int = 0
    @State private var pendingDeployCount: Int = 0
    @State private var isHoveringCoffee = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                Section("Workspace") {
                    Label("Projects", systemImage: "folder.fill")
                        .tag(SidebarSection.projects)

                    Label {
                        Text("Tasks")
                    } icon: {
                        Image(systemName: "checklist")
                    }
                    .badge(activeTaskCount > 0 ? activeTaskCount : 0)
                    .tag(SidebarSection.tasks)

                    Label("Automations", systemImage: "gearshape.2")
                        .tag(SidebarSection.automationFlows)

                    Label("Archive", systemImage: "archivebox")
                        .badge(archivedTaskCount > 0 ? archivedTaskCount : 0)
                        .tag(SidebarSection.archive)
                }

                if !projects.isEmpty {
                    Section("Recent") {
                        ForEach(projects.prefix(5)) { project in
                            Label {
                                Text(project.name)
                                    .lineLimit(1)
                            } icon: {
                                Circle()
                                    .fill(project.status.themeColor)
                                    .frame(width: 8, height: 8)
                            }
                            .tag(SidebarSection.projectTasks(project.id))
                        }

                        if totalProjectCount > 5 {
                            Button {
                                selectedSection = .projects
                            } label: {
                                Label("View All (\(totalProjectCount))", systemImage: "ellipsis.circle")
                                    .foregroundStyle(.forgeAmber)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Pipeline") {
                    Label("Git History", systemImage: "arrow.triangle.branch")
                        .tag(SidebarSection.gitGraph)

                    Label {
                        Text("Deployments")
                    } icon: {
                        Image(systemName: "arrow.up.circle")
                    }
                    .badge(pendingDeployCount > 0 ? pendingDeployCount : 0)
                    .tag(SidebarSection.deploys)
                }

                Section("Monitor") {
                    Label {
                        HStack {
                            Text("Agents")
                            Spacer()
                            if let orchestrator, orchestrator.isRunning {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.forgeSuccess)
                                        .frame(width: 6, height: 6)
                                    if orchestrator.activeRunners.count > 0 {
                                        Text("\(orchestrator.activeRunners.count)")
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } icon: {
                        Image(systemName: "cpu")
                    }
                    .tag(SidebarSection.agents)
                }

                Section("Library") {
                    Label("Prompts", systemImage: "text.book.closed")
                        .tag(SidebarSection.prompts)

                    Label("Assets", systemImage: "photo.on.rectangle.angled")
                        .tag(SidebarSection.assets)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom bar
            bottomPanel
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            brandHeader
        }
        .task { await observeProjects() }
        .task { await observeActiveTaskCount() }
        .task { await observeArchivedTaskCount() }
        .task { await observePendingDeployCount() }
    }

    // MARK: - Brand Header

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Group {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.forgeAmber)
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("CreedFlow")
                    .font(.system(.headline, weight: .bold))
                Text("AI Orchestrator")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            orchestratorButton

            HStack {
                Button {
                    if let url = URL(string: "https://github.com/fatihkan/creedflow") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                        Text("GitHub")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open GitHub Repository")

                Spacer()

                Button {
                    if let url = URL(string: "https://buymeacoffee.com/fatihkan") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("\u{2615}")
                            .font(.system(size: 12))
                        Text("Buy me a coffee")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(Color.forgeAmber.opacity(isHoveringCoffee ? 0.18 : 0.1))
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color.forgeAmber.opacity(isHoveringCoffee ? 0.3 : 0.15), lineWidth: 0.5)
                            }
                    }
                    .scaleEffect(isHoveringCoffee ? 1.03 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isHoveringCoffee)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringCoffee = $0 }
                .help("Support the project")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Orchestrator Button

    private var orchestratorButton: some View {
        Button {
            Task {
                if let orchestrator {
                    if orchestrator.isRunning {
                        await orchestrator.stop()
                    } else {
                        await orchestrator.start()
                    }
                }
            }
        } label: {
            let isRunning = orchestrator?.isRunning == true
            let accent: Color = isRunning ? .forgeSuccess : .secondary
            HStack(spacing: 8) {
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isRunning ? Color.forgeDanger : Color.forgeSuccess)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isRunning ? "Running" : "Start Orchestrator")
                        .font(.system(size: 12, weight: .medium))
                    if isRunning, let orchestrator, orchestrator.activeRunners.count > 0 {
                        Text("\(orchestrator.activeRunners.count) active tasks")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isRunning {
                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                        .shadow(color: accent.opacity(0.5), radius: 3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(orchestrator?.isRunning == true ? "Stop Orchestrator" : "Start Orchestrator")
    }

    // MARK: - Data Observation

    private func observeProjects() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db -> ([Project], Int) in
            let recent = try Project.order(Column("updatedAt").desc).limit(5).fetchAll(db)
            let count = try Project.fetchCount(db)
            return (recent, count)
        }
        do {
            for try await (value, count) in observation.values(in: db.dbQueue) {
                projects = value
                totalProjectCount = count
            }
        } catch { /* observation error — sidebar badges may be stale */ }
    }

    private func observeActiveTaskCount() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try AgentTask
                .filter(Column("status") == AgentTask.Status.inProgress.rawValue)
                .fetchCount(db)
        }
        do {
            for try await count in observation.values(in: db.dbQueue) {
                activeTaskCount = count
            }
        } catch { /* observation error — sidebar badges may be stale */ }
    }

    private func observeArchivedTaskCount() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try AgentTask
                .filter(Column("archivedAt") != nil)
                .fetchCount(db)
        }
        do {
            for try await count in observation.values(in: db.dbQueue) {
                archivedTaskCount = count
            }
        } catch { /* observation error — sidebar badges may be stale */ }
    }

    private func observePendingDeployCount() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try Deployment
                .filter(Column("status") == Deployment.Status.pending.rawValue)
                .fetchCount(db)
        }
        do {
            for try await count in observation.values(in: db.dbQueue) {
                pendingDeployCount = count
            }
        } catch { /* observation error — sidebar badges may be stale */ }
    }
}

