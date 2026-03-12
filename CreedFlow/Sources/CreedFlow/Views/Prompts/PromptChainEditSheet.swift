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
        var hasCondition: Bool = false
        var conditionField: ChainCondition.ConditionField = .reviewScore
        var conditionOp: ChainCondition.ConditionOperator = .gte
        var conditionValue: String = "7"
        var onFailStepOrder: Int? = nil
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

                            DisclosureGroup(
                                isExpanded: $steps[index].hasCondition
                            ) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Picker("Field", selection: $steps[index].conditionField) {
                                            ForEach(ChainCondition.ConditionField.allCases, id: \.self) { f in
                                                Text(f.rawValue).tag(f)
                                            }
                                        }
                                        .frame(width: 140)

                                        Picker("Op", selection: $steps[index].conditionOp) {
                                            ForEach(ChainCondition.ConditionOperator.allCases, id: \.self) { o in
                                                Text(o.rawValue).tag(o)
                                            }
                                        }
                                        .frame(width: 80)

                                        TextField("Value", text: $steps[index].conditionValue)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                    .font(.footnote)

                                    HStack {
                                        Text("On fail:")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        Picker("Target", selection: $steps[index].onFailStepOrder) {
                                            Text("Fail chain").tag(nil as Int?)
                                            ForEach(Array(steps.enumerated()), id: \.offset) { i, _ in
                                                if i != index {
                                                    Text("Jump to step \(i + 1)").tag(i as Int?)
                                                }
                                            }
                                        }
                                        .frame(width: 160)
                                    }
                                    .font(.footnote)
                                }
                                .padding(.top, 4)
                            } label: {
                                Text("Condition")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
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
                var entry = StepEntry(promptId: step.promptId, transitionNote: step.transitionNote ?? "")
                if let condJSON = step.condition, let cond = ChainCondition.decode(from: condJSON) {
                    entry.hasCondition = true
                    entry.conditionField = cond.field
                    entry.conditionOp = cond.op
                    entry.conditionValue = cond.value.stringValue
                    entry.onFailStepOrder = step.onFailStepOrder
                }
                return entry
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
                        transitionNote: stepEntry.transitionNote.isEmpty ? nil : stepEntry.transitionNote,
                        condition: conditionJSON(for: stepEntry),
                        onFailStepOrder: stepEntry.hasCondition ? stepEntry.onFailStepOrder : nil
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
                        transitionNote: stepEntry.transitionNote.isEmpty ? nil : stepEntry.transitionNote,
                        condition: conditionJSON(for: stepEntry),
                        onFailStepOrder: stepEntry.hasCondition ? stepEntry.onFailStepOrder : nil
                    )
                    try step.insert(dbConn)
                }
            }
        }
        dismiss()
    }

    private func conditionJSON(for entry: StepEntry) -> String? {
        guard entry.hasCondition else { return nil }
        let value: ChainCondition.ConditionValue
        if entry.conditionField == .reviewScore, let d = Double(entry.conditionValue) {
            value = .number(d)
        } else if entry.conditionField == .stepSuccess {
            value = .bool(entry.conditionValue.lowercased() == "true")
        } else {
            value = .string(entry.conditionValue)
        }
        let condition = ChainCondition(field: entry.conditionField, op: entry.conditionOp, value: value)
        guard let data = try? JSONEncoder().encode(condition) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
