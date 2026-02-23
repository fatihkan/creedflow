import SwiftUI
import GRDB

struct PromptsLibraryView: View {
    let appDatabase: AppDatabase?
    @State private var store = PromptStore()
    @State private var searchText = ""
    @State private var selectedSource: Prompt.Source?
    @State private var selectedCategory = "all"
    @State private var showEditSheet = false
    @State private var editingPrompt: Prompt?
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var promptToDelete: Prompt?

    private var filteredPrompts: [Prompt] {
        store.filtered(searchText: searchText, source: selectedSource, category: selectedCategory == "all" ? nil : selectedCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Prompts") {
                HStack(spacing: 8) {
                    if let result = importResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        importCommunityPrompts()
                    } label: {
                        Label("Import Community", systemImage: "arrow.down.circle")
                    }
                    .disabled(isImporting)

                    Button {
                        showEditSheet = true
                    } label: {
                        Label("New Prompt", systemImage: "plus")
                    }
                }
            }
            Divider()
            filterBar
            Divider()
            promptList
        }
        .onAppear {
            if let db = appDatabase {
                store.observe(in: db.dbQueue)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            PromptEditSheet(appDatabase: appDatabase)
        }
        .sheet(item: $editingPrompt) { prompt in
            PromptEditSheet(appDatabase: appDatabase, existing: prompt)
        }
        .confirmationDialog(
            "Delete Prompt",
            isPresented: Binding(
                get: { promptToDelete != nil },
                set: { if !$0 { promptToDelete = nil } }
            ),
            presenting: promptToDelete
        ) { prompt in
            Button("Delete \"\(prompt.title)\"", role: .destructive) {
                delete(prompt)
            }
        } message: { prompt in
            Text("This will permanently delete the prompt \"\(prompt.title)\". This cannot be undone.")
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search prompts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 140)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Picker(selection: $selectedSource) {
                Text("All Sources").tag(nil as Prompt.Source?)
                Text("User").tag(Prompt.Source.user as Prompt.Source?)
                Text("Community").tag(Prompt.Source.community as Prompt.Source?)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)

            if !store.categories.isEmpty {
                Picker(selection: $selectedCategory) {
                    Text("All Categories").tag("all")
                    ForEach(store.categories, id: \.self) { cat in
                        Text(cat.capitalized).tag(cat)
                    }
                } label: {
                    EmptyView()
                }
                .frame(maxWidth: 160)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - List

    private var promptList: some View {
        Group {
            if filteredPrompts.isEmpty {
                ForgeEmptyState(
                    icon: "text.book.closed",
                    title: searchText.isEmpty ? "No Prompts" : "No Results",
                    subtitle: searchText.isEmpty
                        ? "Create a prompt or import community prompts"
                        : "No prompts match \"\(searchText)\"",
                    actionTitle: searchText.isEmpty ? "Import Community" : nil,
                    action: searchText.isEmpty ? { importCommunityPrompts() } : nil
                )
            } else {
                List {
                    ForEach(filteredPrompts) { prompt in
                        PromptRow(
                            prompt: prompt,
                            onToggleFavorite: { toggleFavorite(prompt) },
                            onEdit: { editingPrompt = prompt },
                            onDelete: { promptToDelete = prompt }
                        )
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    // MARK: - Actions

    private func importCommunityPrompts() {
        guard let db = appDatabase else { return }
        isImporting = true
        importResult = nil
        Task {
            do {
                let importer = PromptImporter(dbQueue: db.dbQueue)
                let count = try await importer.importCommunityPrompts()
                importResult = "Imported \(count) prompts"
            } catch {
                importResult = "Import failed: \(error.localizedDescription)"
            }
            isImporting = false
        }
    }

    private func toggleFavorite(_ prompt: Prompt) {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            var updated = prompt
            updated.isFavorite.toggle()
            updated.updatedAt = Date()
            try updated.update(dbConn)
        }
    }

    private func delete(_ prompt: Prompt) {
        guard let db = appDatabase else { return }
        _ = try? db.dbQueue.write { dbConn in
            try prompt.delete(dbConn)
        }
    }
}

// MARK: - Prompt Row

private struct PromptRow: View {
    let prompt: Prompt
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(prompt.title)
                        .font(.headline)
                    if prompt.source == .community {
                        Text("Community")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    if prompt.category != "general" {
                        Text(prompt.category)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(prompt.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let contributor = prompt.contributor, !contributor.isEmpty {
                    Text("by \(contributor)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Button { onToggleFavorite() } label: {
                    Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(prompt.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle favorite")

                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit")

                if prompt.source == .user {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
        }
        .padding(.vertical, 4)
    }
}
