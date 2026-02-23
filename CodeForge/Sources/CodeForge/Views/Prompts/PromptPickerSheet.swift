import SwiftUI
import GRDB

struct PromptPickerSheet: View {
    let appDatabase: AppDatabase?
    let onSelect: (Prompt) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = PromptStore()
    @State private var searchText = ""
    @State private var selectedCategory = "all"

    private var filteredPrompts: [Prompt] {
        store.filtered(searchText: searchText, source: nil, category: selectedCategory == "all" ? nil : selectedCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Prompt")
                        .font(.title3.bold())
                    Text("Choose a prompt template to fill the project description")
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

            // Search + Filter
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search prompts...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(minWidth: 140)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

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

            Divider()

            // Prompt List
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
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredPrompts) { prompt in
                        Button {
                            onSelect(prompt)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(prompt.title)
                                        .font(.headline)
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
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
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
        .frame(width: 550, height: 500)
        .onAppear {
            if let db = appDatabase {
                store.observe(in: db.dbQueue)
            }
        }
    }
}
