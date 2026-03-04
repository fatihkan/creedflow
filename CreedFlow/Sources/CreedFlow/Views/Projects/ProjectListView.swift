import SwiftUI
import GRDB

struct ProjectListView: View {
    @Binding var selectedProjectId: UUID?
    @Binding var selectedTaskId: UUID?
    let appDatabase: AppDatabase?
    var onViewProjectTasks: ((UUID) -> Void)?

    @State private var projects: [Project] = []
    @State private var showNewProject = false
    @State private var showTemplateSelector = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var projectToDelete: Project?
    @AppStorage("preferredEditor") private var preferredEditor = ""

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

                    Menu {
                        Button {
                            showNewProject = true
                        } label: {
                            Label("New Project", systemImage: "plus")
                        }
                        Button {
                            showTemplateSelector = true
                        } label: {
                            Label("New from Template", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Project")
                    .help("Create a new project")
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

                                if !preferredEditor.isEmpty {
                                    Button {
                                        openInEditor(at: project.directoryPath)
                                    } label: {
                                        Label("Open in Editor", systemImage: "chevron.left.forwardslash.chevron.right")
                                    }
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
            ProjectCreationWizard(appDatabase: appDatabase)
        }
        .sheet(isPresented: $showTemplateSelector) {
            ProjectTemplateSelectorSheet(appDatabase: appDatabase) { projectId in
                selectedProjectId = projectId
            }
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

// MARK: - Project Template Selector Sheet

struct ProjectTemplateSelectorSheet: View {
    let appDatabase: AppDatabase?
    var onCreated: ((UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: ProjectTemplate?
    @State private var projectName: String = ""
    @State private var errorMessage: String?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New from Template")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if let template = selectedTemplate {
                // Configuration step
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        selectedTemplate = nil
                    } label: {
                        Label("Back to Templates", systemImage: "chevron.left")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Image(systemName: template.icon)
                            .font(.title2)
                            .foregroundStyle(.forgeAmber)
                        VStack(alignment: .leading) {
                            Text(template.name).font(.headline)
                            Text(template.description).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    TextField("Project Name", text: $projectName)
                        .textFieldStyle(.roundedBorder)

                    Text("This will create \(template.features.count) features with \(template.features.flatMap(\.tasks).count) tasks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let errorMessage {
                        ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                    }

                    HStack {
                        Spacer()
                        Button {
                            Task { await createFromTemplate(template) }
                        } label: {
                            if isCreating {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Create Project")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.forgeAmber)
                        .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                    }
                }
                .padding()
            } else {
                // Template grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(ProjectTemplate.builtInTemplates) { template in
                            Button {
                                selectedTemplate = template
                                projectName = ""
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: template.icon)
                                            .font(.title3)
                                            .foregroundStyle(.forgeAmber)
                                        Spacer()
                                        Text(template.projectType.rawValue)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(template.name)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text(template.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(template.techStack)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.quaternary, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 500, height: 420)
    }

    private func createFromTemplate(_ template: ProjectTemplate) async {
        guard let db = appDatabase else { return }
        let name = projectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isCreating = true
        defer { isCreating = false }

        do {
            let projectId = UUID()
            let projectsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("CreedFlow/projects/\(name)")
            try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)

            try await db.dbQueue.write { dbConn in
                var project = Project(
                    id: projectId,
                    name: name,
                    description: template.description,
                    techStack: template.techStack,
                    directoryPath: projectsDir.path,
                    projectType: template.projectType
                )
                try project.insert(dbConn)

                for templateFeature in template.features {
                    let featureId = UUID()
                    var feature = Feature(
                        id: featureId,
                        projectId: projectId,
                        name: templateFeature.name,
                        description: templateFeature.description
                    )
                    try feature.insert(dbConn)

                    for templateTask in templateFeature.tasks {
                        var task = AgentTask(
                            projectId: projectId,
                            featureId: featureId,
                            agentType: templateTask.agentType,
                            title: templateTask.title,
                            description: templateTask.description,
                            priority: templateTask.priority
                        )
                        try task.insert(dbConn)
                    }
                }
            }

            onCreated?(projectId)
            dismiss()
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !project.techStack.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 11))
                        Text(project.techStack)
                    }
                    .font(.caption)
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
