import SwiftUI
import GRDB

struct PromptPickerSheet: View {
    let appDatabase: AppDatabase?
    let projectId: UUID?
    let projectName: String?
    let techStack: String?
    let projectType: String?
    let onSelect: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = PromptStore()
    @State private var chainStore = PromptChainStore()
    @State private var searchText = ""
    @State private var selectedCategory = "all"
    @State private var selectedTag = ""
    @State private var selectedTab = 0 // 0 = prompts, 1 = chains
    @State private var promptForVariables: Prompt?
    @State private var chainContentForVariables: String?
    @State private var chainCategoryForVariables: String?
    @State private var chainForVariables: PromptChain?

    init(
        appDatabase: AppDatabase?,
        projectId: UUID? = nil,
        projectName: String? = nil,
        techStack: String? = nil,
        projectType: String? = nil,
        onSelect: @escaping (String, String?) -> Void
    ) {
        self.appDatabase = appDatabase
        self.projectId = projectId
        self.projectName = projectName
        self.techStack = techStack
        self.projectType = projectType
        self.onSelect = onSelect
    }

    private var filteredPrompts: [Prompt] {
        store.filtered(
            searchText: searchText,
            source: nil,
            category: selectedCategory == "all" ? nil : selectedCategory,
            tag: selectedTag.isEmpty ? nil : selectedTag
        )
    }

    private var builtInValues: [String: String] {
        TemplateVariableResolver.builtInValues(
            projectName: projectName,
            techStack: techStack,
            projectType: projectType
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Prompt")
                        .font(.title3.bold())
                    Text("Choose a prompt template to fill the project description")
                        .font(.footnote)
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

            // Tab selector
            Picker("View", selection: $selectedTab) {
                Text("Prompts").tag(0)
                Text("Chains").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            .padding(.horizontal)
            .padding(.top, 8)

            // Search + Filter
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(minWidth: 100)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                if selectedTab == 0 {
                    if !store.categories.isEmpty {
                        Picker(selection: $selectedCategory) {
                            Text("All Categories").tag("all")
                            ForEach(store.categories, id: \.self) { cat in
                                Text(cat.capitalized).tag(cat)
                            }
                        } label: {
                            EmptyView()
                        }
                        .frame(maxWidth: 140)
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
                        .frame(maxWidth: 120)
                    }
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if selectedTab == 0 {
                promptListView
            } else {
                chainListView
            }

            Divider()

            // Cancel
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 580, height: 540)
        .onAppear {
            if let db = appDatabase {
                store.observe(in: db.dbQueue)
                chainStore.observe(in: db.dbQueue)
            }
        }
        .sheet(item: $promptForVariables) { prompt in
            TemplateVariableInputView(
                template: prompt.content,
                builtInValues: builtInValues
            ) { resolved in
                recordUsage(promptId: prompt.id)
                onSelect(resolved, prompt.category)
                dismiss()
            }
        }
        .sheet(isPresented: Binding(
            get: { chainContentForVariables != nil },
            set: { if !$0 { chainContentForVariables = nil; chainCategoryForVariables = nil; chainForVariables = nil } }
        )) {
            if let content = chainContentForVariables {
                TemplateVariableInputView(
                    template: content,
                    builtInValues: builtInValues
                ) { resolved in
                    if let chain = chainForVariables {
                        recordChainUsage(chain: chain)
                    }
                    onSelect(resolved, chainCategoryForVariables)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Prompt List

    private var promptListView: some View {
        Group {
            if filteredPrompts.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No Prompts Available" : "No Results")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty
                         ? "Import community prompts from the Prompts library first"
                         : "No prompts match \"\(searchText)\"")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredPrompts) { prompt in
                        Button {
                            selectPrompt(prompt)
                        } label: {
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
                                    if prompt.category != "general" {
                                        Text(prompt.category)
                                            .font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.secondary.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                // Tag badges
                                let tags = store.promptTags[prompt.id] ?? []
                                if !tags.isEmpty {
                                    HStack(spacing: 3) {
                                        ForEach(tags.prefix(4), id: \.self) { tag in
                                            Text(tag)
                                                .font(.system(size: 8, weight: .medium))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(.teal.opacity(0.12), in: Capsule())
                                                .foregroundStyle(.teal)
                                        }
                                    }
                                }

                                Text(prompt.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    // MARK: - Chain List

    private var chainListView: some View {
        Group {
            if chainStore.chains.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No Chains Available")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Create chains in the Prompts library to compose multiple prompts")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List {
                    ForEach(chainStore.chains) { chain in
                        Button {
                            selectChain(chain)
                        } label: {
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
                                }
                                if !chain.description.isEmpty {
                                    Text(chain.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    // MARK: - Selection Logic

    private func selectPrompt(_ prompt: Prompt) {
        let variables = TemplateVariableResolver.extractVariables(from: prompt.content)
        if variables.isEmpty {
            recordUsage(promptId: prompt.id)
            onSelect(prompt.content, prompt.category)
            dismiss()
        } else {
            promptForVariables = prompt
        }
    }

    private func selectChain(_ chain: PromptChain) {
        guard let db = appDatabase else { return }
        guard let content = try? chainStore.composeChainContent(chainId: chain.id, in: db.dbQueue),
              !content.isEmpty else { return }

        let variables = TemplateVariableResolver.extractVariables(from: content)
        if variables.isEmpty {
            recordChainUsage(chain: chain)
            onSelect(content, chain.category)
            dismiss()
        } else {
            chainContentForVariables = content
            chainCategoryForVariables = chain.category
            chainForVariables = chain
        }
    }

    private func recordUsage(promptId: UUID) {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            let usage = PromptUsage(promptId: promptId, projectId: projectId)
            try usage.insert(dbConn)
        }
    }

    private func recordChainUsage(chain: PromptChain) {
        guard let db = appDatabase else { return }
        let steps = chainStore.steps[chain.id] ?? []
        try? db.dbQueue.write { dbConn in
            for step in steps {
                let usage = PromptUsage(promptId: step.promptId, projectId: projectId, chainId: chain.id)
                try usage.insert(dbConn)
            }
        }
    }
}
