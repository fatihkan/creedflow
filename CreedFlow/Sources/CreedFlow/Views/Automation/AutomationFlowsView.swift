import SwiftUI
import GRDB

/// Sidebar section view for automation projects — lists automation projects and their tasks.
struct AutomationFlowsView: View {
    let appDatabase: AppDatabase?

    @State private var projects: [Project] = []
    @State private var selectedProjectId: UUID?
    @State private var tasks: [AgentTask] = []
    @State private var showNewAutomation = false

    var body: some View {
        HSplitView {
            // Left: automation projects list
            VStack(spacing: 0) {
                ForgeToolbar(title: "Automations") {
                    Button {
                        showNewAutomation = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New Automation")
                }
                Divider()

                if projects.isEmpty {
                    ForgeEmptyState(
                        icon: "gearshape.2",
                        title: "No Automations",
                        subtitle: "Create an automation project to get started",
                        actionTitle: "New Automation",
                        action: { showNewAutomation = true }
                    )
                } else {
                    List(selection: $selectedProjectId) {
                        ForEach(projects) { project in
                            HStack(spacing: 8) {
                                Image(systemName: "gearshape.2")
                                    .foregroundStyle(.forgeAmber)
                                    .font(.system(size: 14))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name)
                                        .font(.system(.body, weight: .medium))
                                        .lineLimit(1)
                                    Text(project.status.displayName)
                                        .font(.caption)
                                        .foregroundStyle(project.status.themeColor)
                                }
                            }
                            .tag(project.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            // Right: selected project's tasks in sequential order
            VStack(spacing: 0) {
                if let projectId = selectedProjectId,
                   let project = projects.first(where: { $0.id == projectId }) {
                    ForgeToolbar(title: project.name) {}
                    Divider()

                    if tasks.isEmpty {
                        ForgeEmptyState(
                            icon: "checklist",
                            title: "No Steps",
                            subtitle: "This automation has no tasks yet"
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                                    HStack(spacing: 10) {
                                        // Step number
                                        Text("\(index + 1)")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .frame(width: 22, height: 22)
                                            .background(task.status.themeColor)
                                            .clipShape(Circle())

                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                Image(systemName: task.agentType.icon)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(task.agentType.themeColor)
                                                Text(task.title)
                                                    .font(.system(.footnote, weight: .medium))
                                                    .lineLimit(1)
                                            }

                                            Text(task.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }

                                        Spacer()

                                        Text(task.status.displayName)
                                            .forgeBadge(color: task.status.themeColor)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                } else {
                    ForgeEmptyState(
                        icon: "gearshape.2",
                        title: "Select an Automation",
                        subtitle: "Choose an automation from the list to view its steps"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewAutomation) {
            ProjectCreationWizard(appDatabase: appDatabase, initialProjectType: .automation)
        }
        .task {
            await observeProjects()
        }
        .task(id: selectedProjectId) {
            await observeTasks()
        }
    }

    // MARK: - Observation

    private func observeProjects() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try Project
                .filter(Column("projectType") == Project.ProjectType.automation.rawValue)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                projects = value
            }
        } catch { /* sidebar observation error */ }
    }

    private func observeTasks() async {
        guard let db = appDatabase, let pid = selectedProjectId else {
            tasks = []
            return
        }
        let observation = ValueObservation.tracking { db in
            try AgentTask
                .filter(Column("projectId") == pid)
                .filter(Column("archivedAt") == nil)
                .order(Column("priority").desc, Column("createdAt").asc)
                .fetchAll(db)
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                tasks = value
            }
        } catch { /* observation error */ }
    }
}
