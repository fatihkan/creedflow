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
                Text("New Project")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            Form {
                TextField("Project Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                TextField("Tech Stack (e.g., React, Node.js, PostgreSQL)", text: $techStack)
                    .textFieldStyle(.roundedBorder)

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Create Project") {
                    Task { await createProject() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || description.isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
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
