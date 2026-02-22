import SwiftUI
import GRDB

struct ProjectListView: View {
    @Binding var selectedProjectId: UUID?
    let appDatabase: AppDatabase?
    @State private var projects: [Project] = []
    @State private var showNewProject = false

    var body: some View {
        List(selection: $selectedProjectId) {
            ForEach(projects) { project in
                ProjectRowView(project: project)
                    .tag(project.id)
            }
        }
        .listStyle(.inset)
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewProject = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(appDatabase: appDatabase)
        }
        .task {
            await loadProjects()
        }
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder.badge.plus",
                    description: Text("Create your first project to get started")
                )
            }
        }
    }

    private func loadProjects() async {
        guard let db = appDatabase else { return }
        do {
            projects = try await db.dbQueue.read { db in
                try Project.order(Column("updatedAt").desc).fetchAll(db)
            }
        } catch {
            projects = []
        }
    }
}

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name)
                    .font(.headline)
                Spacer()
                StatusBadge(status: project.status.rawValue)
            }
            Text(project.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !project.techStack.isEmpty {
                Text(project.techStack)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
