import SwiftUI
import GRDB

struct PromptEditSheet: View {
    let appDatabase: AppDatabase?
    let existing: Prompt?
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var content = ""
    @State private var category = "general"
    @State private var tagsText = ""
    @State private var changeNote = ""
    @State private var versionHistory: [PromptVersion] = []
    @State private var showVersionHistory = false

    init(appDatabase: AppDatabase?, existing: Prompt? = nil) {
        self.appDatabase = appDatabase
        self.existing = existing
    }

    private var detectedVariables: [String] {
        TemplateVariableResolver.extractVariables(from: content)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Prompt Info") {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                    TextField("Category", text: $category)
                        .textFieldStyle(.roundedBorder)
                    TextField("Tags (comma-separated)", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                    if !parsedTags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(parsedTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                }

                if !detectedVariables.isEmpty {
                    Section("Template Variables") {
                        HStack(spacing: 4) {
                            ForEach(detectedVariables, id: \.self) { variable in
                                HStack(spacing: 2) {
                                    Text("{{\(variable)}}")
                                        .font(.system(size: 10, design: .monospaced))
                                    if TemplateVariableResolver.builtInVariables.contains(variable) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 7))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.12), in: Capsule())
                                .foregroundStyle(.orange)
                            }
                        }
                        Text("Variables with bolt icon are auto-filled from project context")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if existing != nil {
                    Section("Change Note") {
                        TextField("Describe what changed (optional)", text: $changeNote)
                            .textFieldStyle(.roundedBorder)
                    }

                    if !versionHistory.isEmpty {
                        DisclosureGroup("Version History (\(versionHistory.count))", isExpanded: $showVersionHistory) {
                            ForEach(versionHistory) { ver in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("v\(ver.version) — \(ver.title)")
                                            .font(.caption.bold())
                                        if let note = ver.changeNote, !note.isEmpty {
                                            Text(note)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(ver.createdAt, style: .date)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Button("Revert") {
                                        revertToVersion(ver)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if let existing {
                    Text("v\(existing.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(existing == nil ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty || content.isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 560)
        .onAppear {
            if let existing {
                title = existing.title
                content = existing.content
                category = existing.category
                loadTags()
                loadVersionHistory()
            }
        }
    }

    private var parsedTags: [String] {
        tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func loadTags() {
        guard let db = appDatabase, let existing else { return }
        let tags = try? db.dbQueue.read { dbConn in
            try PromptTag
                .filter(Column("promptId") == existing.id)
                .fetchAll(dbConn)
        }
        if let tags {
            tagsText = tags.map(\.tag).joined(separator: ", ")
        }
    }

    private func loadVersionHistory() {
        guard let db = appDatabase, let existing else { return }
        versionHistory = (try? PromptStore().fetchVersionHistory(for: existing.id, in: db.dbQueue)) ?? []
    }

    private func revertToVersion(_ version: PromptVersion) {
        title = version.title
        content = version.content
        changeNote = "Reverted to v\(version.version)"
    }

    private func save() {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            if var prompt = existing {
                // Snapshot current version before editing
                let snapshot = PromptVersion(
                    promptId: prompt.id,
                    version: prompt.version,
                    title: prompt.title,
                    content: prompt.content,
                    changeNote: changeNote.isEmpty ? nil : changeNote
                )
                try snapshot.insert(dbConn)

                prompt.title = title
                prompt.content = content
                prompt.category = category
                prompt.version += 1
                prompt.updatedAt = Date()
                try prompt.update(dbConn)

                // Sync tags
                try PromptTag
                    .filter(Column("promptId") == prompt.id)
                    .deleteAll(dbConn)
                for tag in parsedTags {
                    try PromptTag(promptId: prompt.id, tag: tag).insert(dbConn)
                }
            } else {
                var prompt = Prompt(
                    title: title,
                    content: content,
                    source: .user,
                    category: category
                )
                try prompt.insert(dbConn)

                // Insert tags
                for tag in parsedTags {
                    try PromptTag(promptId: prompt.id, tag: tag).insert(dbConn)
                }
            }
        }
        dismiss()
    }
}
