import SwiftUI
import GRDB

struct ProjectListView: View {
    @Binding var selectedProjectId: UUID?
    @Binding var selectedTaskId: UUID?
    let appDatabase: AppDatabase?
    var onViewProjectTasks: ((UUID) -> Void)?

    @State private var projects: [Project] = []
    @State private var showNewProject = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var projectToDelete: Project?

    private var filteredProjects: [Project] {
        if searchText.isEmpty { return projects }
        return projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.techStack.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Projects") {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 140)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Button {
                        showNewProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            Divider()

            if projects.isEmpty && errorMessage == nil {
                ForgeEmptyState(
                    icon: "folder.badge.plus",
                    title: "No Projects",
                    subtitle: "Create your first project to get started",
                    actionTitle: "New Project",
                    action: { showNewProject = true }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if let errorMessage {
                            ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        if !projects.isEmpty && filteredProjects.isEmpty {
                            ForgeEmptyState(
                                icon: "magnifyingglass",
                                title: "No Results",
                                subtitle: "No projects match \"\(searchText)\""
                            )
                            .frame(height: 200)
                        }

                        ForEach(filteredProjects) { project in
                            ProjectRowView(
                                project: project,
                                isSelected: selectedProjectId == project.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedProjectId = project.id
                                selectedTaskId = nil
                            }
                            .contextMenu {
                                Button {
                                    onViewProjectTasks?(project.id)
                                } label: {
                                    Label("View Tasks", systemImage: "checklist")
                                }

                                Divider()

                                Button {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: project.directoryPath))
                                } label: {
                                    Label("Open in Finder", systemImage: "folder")
                                }

                                Button {
                                    openTerminal(at: project.directoryPath)
                                } label: {
                                    Label("Open in Terminal", systemImage: "terminal")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    projectToDelete = project
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(appDatabase: appDatabase)
        }
        .confirmationDialog(
            "Delete Project",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            presenting: projectToDelete
        ) { project in
            Button("Delete \"\(project.name)\"", role: .destructive) {
                deleteProject(project)
            }
        } message: { project in
            Text("This will permanently delete \"\(project.name)\" and all its tasks, reviews, logs, and deployments. This cannot be undone.")
        }
        .task {
            await observeProjects()
        }
    }

    private func observeProjects() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try Project.order(Column("updatedAt").desc).fetchAll(db)
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                projects = value
                errorMessage = nil
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

    private func deleteProject(_ project: Project) {
        guard let db = appDatabase else { return }
        _ = try? db.dbQueue.write { dbConn in
            try project.delete(dbConn)
        }
        if selectedProjectId == project.id {
            selectedProjectId = nil
        }
    }
}

struct ProjectRowView: View {
    let project: Project
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(project.status.themeColor)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(project.name)
                        .font(.system(.body, design: .default, weight: .semibold))
                    Spacer()
                    Text(project.status.displayName)
                        .forgeBadge(color: project.status.themeColor)
                }

                Text(project.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !project.techStack.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 9))
                        Text(project.techStack)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.forgeSelection : Color.clear)
        .contentShape(Rectangle())
    }
}
