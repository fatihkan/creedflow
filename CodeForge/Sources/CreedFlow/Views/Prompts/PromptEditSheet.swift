import SwiftUI
import GRDB

struct PromptEditSheet: View {
    let appDatabase: AppDatabase?
    let existing: Prompt?
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var content = ""
    @State private var category = "general"

    init(appDatabase: AppDatabase?, existing: Prompt? = nil) {
        self.appDatabase = appDatabase
        self.existing = existing
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Prompt Info") {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                    TextField("Category", text: $category)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 160)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(existing == nil ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty || content.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 420)
        .onAppear {
            if let existing {
                title = existing.title
                content = existing.content
                category = existing.category
            }
        }
    }

    private func save() {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            if var prompt = existing {
                prompt.title = title
                prompt.content = content
                prompt.category = category
                prompt.updatedAt = Date()
                try prompt.update(dbConn)
            } else {
                var prompt = Prompt(
                    title: title,
                    content: content,
                    source: .user,
                    category: category
                )
                try prompt.insert(dbConn)
            }
        }
        dismiss()
    }
}
