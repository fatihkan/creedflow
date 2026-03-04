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
    @State private var selectedVersionsForDiff: Set<UUID> = []
    @State private var showDiffSheet = false
    @State private var diffOldVersion: PromptVersion?
    @State private var diffNewVersion: PromptVersion?
    @State private var previousContent: String = ""
    @State private var previousTitle: String = ""
    @Environment(\.undoManager) private var undoManager

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
                                    .font(.system(size: 11, weight: .medium))
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
                                        .font(.system(size: 12, design: .monospaced))
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
                            .font(.caption)
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
                            if selectedVersionsForDiff.count == 2 {
                                Button("Compare Selected") {
                                    presentDiff()
                                }
                                .font(.footnote)
                                .buttonStyle(.bordered)
                                .padding(.bottom, 4)
                            }

                            ForEach(versionHistory) { ver in
                                HStack {
                                    Toggle(isOn: Binding(
                                        get: { selectedVersionsForDiff.contains(ver.id) },
                                        set: { isOn in
                                            if isOn {
                                                if selectedVersionsForDiff.count >= 2 {
                                                    selectedVersionsForDiff.removeFirst()
                                                }
                                                selectedVersionsForDiff.insert(ver.id)
                                            } else {
                                                selectedVersionsForDiff.remove(ver.id)
                                            }
                                        }
                                    )) {
                                        EmptyView()
                                    }
                                    .toggleStyle(.checkbox)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("v\(ver.version) — \(ver.title)")
                                            .font(.footnote.bold())
                                        if let note = ver.changeNote, !note.isEmpty {
                                            Text(note)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(ver.createdAt, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Button("Revert") {
                                        revertToVersion(ver)
                                    }
                                    .font(.footnote)
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(existing == nil ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty || content.isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 560)
        .sheet(isPresented: $showDiffSheet) {
            if let old = diffOldVersion, let new = diffNewVersion {
                PromptVersionDiffView(oldVersion: old, newVersion: new)
            }
        }
        .onAppear {
            if let existing {
                title = existing.title
                content = existing.content
                category = existing.category
                previousTitle = existing.title
                previousContent = existing.content
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

    private func presentDiff() {
        let selected = versionHistory.filter { selectedVersionsForDiff.contains($0.id) }
        guard selected.count == 2 else { return }
        let sorted = selected.sorted { $0.version < $1.version }
        diffOldVersion = sorted[0]
        diffNewVersion = sorted[1]
        showDiffSheet = true
    }

    private func revertToVersion(_ version: PromptVersion) {
        title = version.title
        content = version.content
        changeNote = "Reverted to v\(version.version)"
    }

    private func save() {
        guard let db = appDatabase else { return }
        let savedPreviousTitle = previousTitle
        let savedPreviousContent = previousContent
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

                // Register undo: revert prompt to previous title/content
                if let undoManager {
                    let promptId = prompt.id
                    undoManager.registerUndo(withTarget: PromptUndoTarget.shared) { _ in
                        try? db.dbQueue.write { dbConn in
                            guard var p = try Prompt.fetchOne(dbConn, id: promptId) else { return }
                            p.title = savedPreviousTitle
                            p.content = savedPreviousContent
                            p.version += 1
                            p.updatedAt = Date()
                            try p.update(dbConn)
                        }
                    }
                    undoManager.setActionName("Edit Prompt")
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

private final class PromptUndoTarget: NSObject {
    static let shared = PromptUndoTarget()
}
