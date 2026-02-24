import SwiftUI
import GRDB

struct SidebarView: View {
    @Binding var selectedSection: SidebarSection?
    @Binding var selectedProjectId: UUID?
    let orchestrator: Orchestrator?
    let appDatabase: AppDatabase?

    @State private var projects: [Project] = []
    @State private var totalProjectCount: Int = 0
    @State private var pendingReviewCount: Int = 0
    @State private var activeTaskCount: Int = 0
    @State private var pendingDeployCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar list
            List(selection: $selectedSection) {
                workspaceSection
                projectShortcuts
                pipelineSection
                monitorSection
                promptsSection
                settingsSection
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Bottom bar — orchestrator control
            HStack(spacing: 8) {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(.forgeAmber)
                    .font(.caption)
                Text("Creed")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                orchestratorButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await observeProjects()
        }
        .task {
            await observeReviewCount()
        }
        .task {
            await observeActiveTaskCount()
        }
        .task {
            await observePendingDeployCount()
        }
    }

    // MARK: - Sections

    private var workspaceSection: some View {
        Section("Workspace") {
            Label("Projects", systemImage: "folder.fill")
                .tag(SidebarSection.projects)

            HStack {
                Label("Tasks", systemImage: "checklist")
                Spacer()
                if activeTaskCount > 0 {
                    Text("\(activeTaskCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.forgeInfo, in: Capsule())
                }
            }
            .tag(SidebarSection.tasks)
        }
    }

    @ViewBuilder
    private var projectShortcuts: some View {
        if !projects.isEmpty {
            Section("Recent Projects") {
                ForEach(projects.prefix(5)) { project in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(project.status.themeColor)
                            .frame(width: 6, height: 6)
                        Text(project.name)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .tag(SidebarSection.projectTasks(project.id))
                }
                if totalProjectCount > 5 {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                            .font(.caption2)
                        Text("View All Projects")
                            .font(.caption)
                    }
                    .foregroundStyle(.forgeAmber)
                    .tag(SidebarSection.projects)
                }
            }
        }
    }

    private var pipelineSection: some View {
        Section("Pipeline") {
            HStack {
                Label("Reviews", systemImage: "checkmark.shield")
                Spacer()
                if pendingReviewCount > 0 {
                    Text("\(pendingReviewCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.forgeWarning, in: Capsule())
                }
            }
            .tag(SidebarSection.reviews)

            HStack {
                Label("Deployments", systemImage: "arrow.up.circle")
                Spacer()
                if pendingDeployCount > 0 {
                    Text("\(pendingDeployCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.forgeAmber, in: Capsule())
                }
            }
            .tag(SidebarSection.deploys)
        }
    }

    private var monitorSection: some View {
        Section("Monitor") {
            HStack {
                Label("Agents", systemImage: "cpu")
                Spacer()
                agentIndicator
            }
            .tag(SidebarSection.agents)

            Label("Costs", systemImage: "dollarsign.circle")
                .tag(SidebarSection.costs)
        }
    }

    private var promptsSection: some View {
        Section("Library") {
            Label("Prompts", systemImage: "text.book.closed")
                .tag(SidebarSection.prompts)
        }
    }

    private var settingsSection: some View {
        Section {
            Label("Settings", systemImage: "gear")
                .tag(SidebarSection.settings)
        }
    }

    @ViewBuilder
    private var agentIndicator: some View {
        if let orchestrator, orchestrator.isRunning {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.forgeSuccess)
                    .frame(width: 6, height: 6)
                if orchestrator.activeRunners.count > 0 {
                    Text("\(orchestrator.activeRunners.count)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

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
            Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                .foregroundStyle(isRunning ? Color.forgeDanger : Color.forgeSuccess)
                .font(.body)
        }
        .buttonStyle(.plain)
        .help(orchestrator?.isRunning == true ? "Stop Orchestrator" : "Start Orchestrator")
        .accessibilityLabel(orchestrator?.isRunning == true ? "Stop Orchestrator" : "Start Orchestrator")
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

    private func observeReviewCount() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try Review
                .filter(Column("verdict") != Review.Verdict.pass.rawValue)
                .fetchCount(db)
        }
        do {
            for try await count in observation.values(in: db.dbQueue) {
                pendingReviewCount = count
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
