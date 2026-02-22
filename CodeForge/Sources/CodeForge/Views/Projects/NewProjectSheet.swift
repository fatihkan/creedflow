import SwiftUI
import GRDB

struct NewProjectSheet: View {
    let appDatabase: AppDatabase?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var techStack = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Project")
                        .font(.title3.bold())
                    Text("Create a new project for CodeForge to manage")
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
                }

                Section("Description") {
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
        .frame(width: 500, height: 480)
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

            try await db.dbQueue.write { dbConn in
                var project = Project(
                    name: name,
                    description: description,
                    techStack: techStack,
                    directoryPath: path
                )
                try project.insert(dbConn)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
