import SwiftUI
import GRDB

struct ProjectListView: View {
    @Binding var selectedProjectId: UUID?
    @Binding var selectedTaskId: UUID?
    let appDatabase: AppDatabase?

    @State private var projects: [Project] = []
    @State private var showNewProject = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if projects.isEmpty && errorMessage == nil {
                ForgeEmptyState(
                    icon: "folder.badge.plus",
                    title: "No Projects",
                    subtitle: "Create your first project to get started"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if let errorMessage {
                            ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        ForEach(projects) { project in
                            ProjectRowView(
                                project: project,
                                isSelected: selectedProjectId == project.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedProjectId = project.id
                                selectedTaskId = nil
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
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
        .background(isSelected ? Color.forgeAmber.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }
}
