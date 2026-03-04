import SwiftUI
import GRDB
import AppKit

enum PromptSortOrder: String, CaseIterable {
    case alphabetical = "A-Z"
    case usageCount = "Usage"
    case successRate = "Success"
    case reviewScore = "Score"
}

struct PromptsLibraryView: View {
    let appDatabase: AppDatabase?
    @State private var store = PromptStore()
    @State private var chainStore = PromptChainStore()
    @State private var searchText = ""
    @State private var selectedSource: Prompt.Source?
    @State private var selectedCategory = "all"
    @State private var selectedTag = ""
    @State private var selectedTab = 0 // 0 = prompts, 1 = chains, 2 = effectiveness
    @State private var showEditSheet = false
    @State private var editingPrompt: Prompt?
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var promptToDelete: Prompt?
    @State private var showChainEditSheet = false
    @State private var editingChain: PromptChain?
    @State private var chainToDelete: PromptChain?
    @State private var sortOrder: PromptSortOrder = .alphabetical

    private var filteredPrompts: [Prompt] {
        let base = store.filtered(
            searchText: searchText,
            source: selectedSource,
            category: selectedCategory == "all" ? nil : selectedCategory,
            tag: selectedTag.isEmpty ? nil : selectedTag
        )
        switch sortOrder {
        case .alphabetical:
            return base
        case .usageCount:
            return base.sorted { (store.promptStats[$0.id]?.usageCount ?? 0) > (store.promptStats[$1.id]?.usageCount ?? 0) }
        case .successRate:
            return base.sorted { (store.promptStats[$0.id]?.successRate ?? -1) > (store.promptStats[$1.id]?.successRate ?? -1) }
        case .reviewScore:
            return base.sorted { (store.promptStats[$0.id]?.averageReviewScore ?? -1) > (store.promptStats[$1.id]?.averageReviewScore ?? -1) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Prompts") {
                HStack(spacing: 8) {
                    if let result = importResult {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if selectedTab != 2 {
                        Button {
                            importCommunityPrompts()
                        } label: {
                            Label("Import Community", systemImage: "arrow.down.circle")
                        }
                        .disabled(isImporting)

                        if selectedTab == 0 {
                            Button {
                                exportPrompts()
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .disabled(filteredPrompts.isEmpty)

                            Button {
                                importPromptsFromJSON()
                            } label: {
                                Label("Import JSON", systemImage: "square.and.arrow.down")
                            }

                            Button {
                                showEditSheet = true
                            } label: {
                                Label("New Prompt", systemImage: "plus")
                            }
                        } else {
                            Button {
                                showChainEditSheet = true
                            } label: {
                                Label("New Chain", systemImage: "plus")
                            }
                        }
                    }
                }
            }
            Divider()

            // Tab selector
            Picker("View", selection: $selectedTab) {
                Text("Prompts").tag(0)
                Text("Chains").tag(1)
                Text("Effectiveness").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .padding(.horizontal)
            .padding(.top, 8)

            if selectedTab == 0 {
                filterBar
                Divider()
                promptList
            } else if selectedTab == 1 {
                Divider()
                chainList
            } else {
                Divider()
                PromptEffectivenessDashboardView(appDatabase: appDatabase)
            }
        }
        .onAppear {
            if let db = appDatabase {
                store.observe(in: db.dbQueue)
                store.observeStats(in: db.dbQueue)
                chainStore.observe(in: db.dbQueue)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            PromptEditSheet(appDatabase: appDatabase)
        }
        .sheet(item: $editingPrompt) { prompt in
            PromptEditSheet(appDatabase: appDatabase, existing: prompt)
        }
        .sheet(isPresented: $showChainEditSheet) {
            PromptChainEditSheet(appDatabase: appDatabase, prompts: store.prompts)
        }
        .sheet(item: $editingChain) { chain in
            PromptChainEditSheet(appDatabase: appDatabase, existing: chain, prompts: store.prompts)
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
        .confirmationDialog(
            "Delete Chain",
            isPresented: Binding(
                get: { chainToDelete != nil },
                set: { if !$0 { chainToDelete = nil } }
            ),
            presenting: chainToDelete
        ) { chain in
            Button("Delete \"\(chain.name)\"", role: .destructive) {
                deleteChain(chain)
            }
        } message: { chain in
            Text("This will permanently delete the chain \"\(chain.name)\". This cannot be undone.")
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

            if !store.allTags.isEmpty {
                Picker(selection: $selectedTag) {
                    Text("All Tags").tag("")
                    ForEach(store.allTags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                } label: {
                    EmptyView()
                }
                .frame(maxWidth: 140)
            }

            Picker(selection: $sortOrder) {
                ForEach(PromptSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            } label: {
                EmptyView()
            }
            .frame(maxWidth: 100)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Prompt List

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
                            tags: store.promptTags[prompt.id] ?? [],
                            usageCount: usageCount(for: prompt),
                            stats: store.promptStats[prompt.id],
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

    // MARK: - Chain List

    private var chainList: some View {
        Group {
            if chainStore.chains.isEmpty {
                ForgeEmptyState(
                    icon: "link",
                    title: "No Chains",
                    subtitle: "Create a chain to compose multiple prompts together",
                    actionTitle: "New Chain",
                    action: { showChainEditSheet = true }
                )
            } else {
                List {
                    ForEach(chainStore.chains) { chain in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(chain.name)
                                        .font(.headline)
                                    let stepCount = chainStore.steps[chain.id]?.count ?? 0
                                    Text("\(stepCount) steps")
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.purple.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.purple)
                                    if chain.category != "general" {
                                        Text(chain.category)
                                            .font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.secondary.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.secondary)
                                    }
                                    let chainUsage = chainUsageCount(for: chain)
                                    if chainUsage > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "chart.bar")
                                                .font(.system(size: 8))
                                            Text("\(chainUsage)")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                if !chain.description.isEmpty {
                                    Text(chain.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Button { editingChain = chain } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .help("Edit")
                                Button(role: .destructive) { chainToDelete = chain } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    // MARK: - Actions

    private func chainUsageCount(for chain: PromptChain) -> Int {
        guard let db = appDatabase else { return 0 }
        return (try? chainStore.fetchChainUsageCount(chainId: chain.id, in: db.dbQueue)) ?? 0
    }

    private func usageCount(for prompt: Prompt) -> Int {
        guard let db = appDatabase else { return 0 }
        return (try? db.dbQueue.read { dbConn in
            try PromptUsage.filter(Column("promptId") == prompt.id).fetchCount(dbConn)
        }) ?? 0
    }

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

    private func exportPrompts() {
        guard appDatabase != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "creedflow-prompts.json"
        panel.title = "Export Prompts"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try PromptExporter.export(prompts: filteredPrompts, tags: store.promptTags)
            try data.write(to: url)
            importResult = "Exported \(filteredPrompts.count) prompts"
        } catch {
            importResult = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importPromptsFromJSON() {
        guard let db = appDatabase else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.title = "Import Prompts"
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let count = try PromptExporter.importPrompts(from: data, into: db.dbQueue)
            importResult = "Imported \(count) prompts"
        } catch {
            importResult = "Import failed: \(error.localizedDescription)"
        }
    }

    private func deleteChain(_ chain: PromptChain) {
        guard let db = appDatabase else { return }
        _ = try? db.dbQueue.write { dbConn in
            try chain.delete(dbConn)
        }
    }
}

// MARK: - Prompt Row

private struct PromptRow: View {
    let prompt: Prompt
    let tags: [String]
    let usageCount: Int
    var stats: PromptStats?
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(prompt.title)
                        .font(.headline)
                    if prompt.version > 1 {
                        Text("v\(prompt.version)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    if prompt.source == .community {
                        Text("Community")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    if prompt.category != "general" {
                        Text(prompt.category)
                            .font(.system(size: 11, weight: .medium))
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

                HStack(spacing: 4) {
                    if !tags.isEmpty {
                        ForEach(tags.prefix(5), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 8, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.teal.opacity(0.12), in: Capsule())
                                .foregroundStyle(.teal)
                        }
                    }
                    if let contributor = prompt.contributor, !contributor.isEmpty {
                        Text("by \(contributor)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if usageCount > 0 {
                        Spacer().frame(width: 4)
                        HStack(spacing: 2) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 8))
                            Text("\(usageCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    if let rate = stats?.successRate {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 8))
                            Text("\(Int(rate * 100))%")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(rate >= 0.7 ? .forgeSuccess : rate >= 0.4 ? .forgeWarning : .forgeDanger)
                    }
                    if let score = stats?.averageReviewScore {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                            Text(String(format: "%.1f", score))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(score >= 7.0 ? .forgeSuccess : score >= 5.0 ? .forgeWarning : .forgeDanger)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Button { onToggleFavorite() } label: {
                    Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(prompt.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(prompt.isFavorite ? "Remove from favorites" : "Add to favorites")
                .help("Toggle favorite")

                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit prompt")
                .help("Edit")

                if prompt.source == .user {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete prompt")
                    .help("Delete")
                }
            }
        }
        .padding(.vertical, 4)
    }
}
