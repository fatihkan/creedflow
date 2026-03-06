import SwiftUI
import GRDB

struct PromptChainEditSheet: View {
    let appDatabase: AppDatabase?
    let existing: PromptChain?
    let prompts: [Prompt]
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var category = "general"
    @State private var steps: [StepEntry] = []

    struct StepEntry: Identifiable, Equatable {
        let id = UUID()
        var promptId: UUID?
        var transitionNote: String = ""
    }

    init(appDatabase: AppDatabase?, existing: PromptChain? = nil, prompts: [Prompt]) {
        self.appDatabase = appDatabase
        self.existing = existing
        self.prompts = prompts
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Chain Info") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("Description", text: $description)
                        .textFieldStyle(.roundedBorder)
                    TextField("Category", text: $category)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Steps") {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Step \(index + 1)")
                                    .font(.footnote.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if steps.count > 1 {
                                    Button {
                                        steps.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }

                            Picker("Prompt", selection: $steps[index].promptId) {
                                Text("Select...").tag(nil as UUID?)
                                ForEach(prompts, id: \.id) { prompt in
                                    Text(prompt.title).tag(prompt.id as UUID?)
                                }
                            }

                            if index > 0 {
                                TextField("Transition note (optional)", text: $steps[index].transitionNote)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.footnote)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        steps.append(StepEntry())
                    } label: {
                        Label("Add Step", systemImage: "plus")
                    }
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
                    .disabled(name.isEmpty || steps.isEmpty || steps.contains(where: { $0.promptId == nil }))
            }
            .padding()
        }
        .frame(width: 520, height: 520)
        .onAppear {
            if let existing {
                name = existing.name
                description = existing.description
                category = existing.category
                loadExistingSteps()
            } else if steps.isEmpty {
                steps = [StepEntry()]
            }
        }
    }

    private func loadExistingSteps() {
        guard let db = appDatabase, let existing else { return }
        let chainSteps = try? db.dbQueue.read { dbConn in
            try PromptChainStep
                .filter(Column("chainId") == existing.id)
                .order(Column("stepOrder").asc)
                .fetchAll(dbConn)
        }
        if let chainSteps, !chainSteps.isEmpty {
            steps = chainSteps.map { step in
                StepEntry(promptId: step.promptId, transitionNote: step.transitionNote ?? "")
            }
        } else {
            steps = [StepEntry()]
        }
    }

    private func save() {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            if var chain = existing {
                chain.name = name
                chain.description = description
                chain.category = category
                chain.updatedAt = Date()
                try chain.update(dbConn)

                // Delete existing steps and recreate
                try PromptChainStep
                    .filter(Column("chainId") == chain.id)
                    .deleteAll(dbConn)

                for (index, stepEntry) in steps.enumerated() {
                    guard let promptId = stepEntry.promptId else { continue }
                    let step = PromptChainStep(
                        chainId: chain.id,
                        promptId: promptId,
                        stepOrder: index,
                        transitionNote: stepEntry.transitionNote.isEmpty ? nil : stepEntry.transitionNote
                    )
                    try step.insert(dbConn)
                }
            } else {
                var chain = PromptChain(
                    name: name,
                    description: description,
                    category: category
                )
                try chain.insert(dbConn)

                for (index, stepEntry) in steps.enumerated() {
                    guard let promptId = stepEntry.promptId else { continue }
                    let step = PromptChainStep(
                        chainId: chain.id,
                        promptId: promptId,
                        stepOrder: index,
                        transitionNote: stepEntry.transitionNote.isEmpty ? nil : stepEntry.transitionNote
                    )
                    try step.insert(dbConn)
                }
            }
        }
        dismiss()
    }
}
