import SwiftUI
import GRDB

struct NewProjectSheet: View {
    let appDatabase: AppDatabase?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var techStack = ""
    @State private var projectType: Project.ProjectType = .software
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showPromptPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Project")
                        .font(.title3.bold())
                    Text("Create a new project for CreedFlow to manage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            // Form
            Form {
                Section("Project Info") {
                    TextField("Project Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Picker("Project Type", selection: $projectType) {
                        ForEach(Project.ProjectType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Description")
                        Spacer()
                        Button {
                            showPromptPicker = true
                        } label: {
                            Label("Use Prompt", systemImage: "text.book.closed")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Section("Tech Stack") {
                    TextField("e.g., React, Node.js, PostgreSQL", text: $techStack)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = errorMessage {
                    ForgeErrorBanner(message: error, onDismiss: { errorMessage = nil })
                }
            }
            .formStyle(.grouped)

            Divider()

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 8)
                }
                Button("Create Project") {
                    Task { await createProject() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.forgeAmber)
                .disabled(name.isEmpty || description.isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 500, height: 540)
        .sheet(isPresented: $showPromptPicker) {
            PromptPickerSheet(appDatabase: appDatabase) { prompt in
                description = prompt.content
                projectType = Self.detectProjectType(from: prompt.category)
            }
        }
    }

    private func createProject() async {
        isCreating = true
        defer { isCreating = false }

        guard let db = appDatabase else {
            errorMessage = "Database not available"
            return
        }

        do {
            let dirService = ProjectDirectoryService()
            let path = try await dirService.createProjectDirectory(name: name)

            // Prepend project type tag so the analyzer knows the context
            let analyzerDescription = "[ProjectType: \(projectType.rawValue)] \(description)"

            try await db.dbQueue.write { dbConn in
                var project = Project(
                    name: name,
                    description: description,
                    techStack: techStack,
                    directoryPath: path,
                    projectType: projectType
                )
                try project.insert(dbConn)

                // Auto-queue analyzer task for the new project
                let analyzerTask = AgentTask(
                    projectId: project.id,
                    agentType: .analyzer,
                    title: "Analyze: \(name)",
                    description: analyzerDescription,
                    priority: 10
                )
                try analyzerTask.insert(dbConn)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Auto-Detection

    /// Maps prompt category to project type
    static func detectProjectType(from category: String) -> Project.ProjectType {
        switch category.lowercased() {
        case "web development", "coding", "vibe coding", "data science",
             "programming", "software", "software engineering", "development":
            return .software
        case "image generation", "image", "ai art", "art":
            return .image
        case "video generation", "video", "video editing":
            return .video
        case "blog writing", "writing", "creative", "academic writing",
             "content", "copywriting", "documentation", "blogging",
             "creative writing", "academic":
            return .content
        default:
            return .general
        }
    }
}

// MARK: - ProjectType Display

extension Project.ProjectType {
    var displayName: String {
        switch self {
        case .software: return "Software"
        case .content: return "Content"
        case .image: return "Image"
        case .video: return "Video"
        case .general: return "General"
        }
    }
}
