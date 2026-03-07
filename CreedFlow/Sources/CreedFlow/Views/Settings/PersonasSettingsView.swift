import SwiftUI
import GRDB

struct PersonasSettingsView: View {
    let appDatabase: AppDatabase?

    @State private var personas: [AgentPersona] = []
    @State private var showingAddSheet = false
    @State private var editingPersona: AgentPersona?
    @State private var deletingPersona: AgentPersona?

    var body: some View {
        Form {
            Section {
                Text(L("personas.description"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if personas.isEmpty {
                    Text(L("personas.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(personas) { persona in
                        PersonaRow(
                            persona: persona,
                            onToggle: { toggleEnabled(persona) },
                            onEdit: { editingPersona = persona },
                            onDelete: { deletingPersona = persona }
                        )
                    }
                }
            } header: {
                HStack {
                    Text(L("personas.title"))
                    Spacer()
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .task { await loadPersonas() }
        .sheet(isPresented: $showingAddSheet) {
            PersonaFormSheet(appDatabase: appDatabase) {
                await loadPersonas()
            }
        }
        .sheet(item: $editingPersona) { persona in
            PersonaFormSheet(appDatabase: appDatabase, editing: persona) {
                await loadPersonas()
            }
        }
        .alert(
            L("personas.confirmDelete"),
            isPresented: Binding(
                get: { deletingPersona != nil },
                set: { if !$0 { deletingPersona = nil } }
            )
        ) {
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("personas.delete"), role: .destructive) {
                if let persona = deletingPersona {
                    deletePersona(persona)
                }
            }
        } message: {
            Text(L("personas.deleteHint"))
        }
    }

    private func loadPersonas() async {
        guard let db = appDatabase else { return }
        do {
            personas = try await db.dbQueue.read { dbConn in
                try AgentPersona.all().fetchAll(dbConn)
            }
        } catch {
            personas = []
        }
    }

    private func toggleEnabled(_ persona: AgentPersona) {
        guard let db = appDatabase else { return }
        var updated = persona
        updated.isEnabled.toggle()
        updated.updatedAt = Date()
        try? db.dbQueue.write { dbConn in
            try updated.update(dbConn)
        }
        Task { await loadPersonas() }
    }

    private func deletePersona(_ persona: AgentPersona) {
        guard let db = appDatabase, !persona.isBuiltIn else { return }
        _ = try? db.dbQueue.write { dbConn in
            try persona.delete(dbConn)
        }
        Task { await loadPersonas() }
    }
}

// MARK: - Persona Row

private struct PersonaRow: View {
    let persona: AgentPersona
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(persona.name)
                        .font(.subheadline.weight(.medium))
                    if persona.isBuiltIn {
                        Text(L("personas.builtIn"))
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                if !persona.description.isEmpty {
                    Text(persona.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !persona.agentTypes.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(persona.agentTypes, id: \.rawValue) { type in
                            Text(type.rawValue)
                                .font(.system(size: 10))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.purple.opacity(0.1), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { persona.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button { onEdit() } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)

            if !persona.isBuiltIn {
                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Persona Form Sheet

private struct PersonaFormSheet: View {
    let appDatabase: AppDatabase?
    var editing: AgentPersona?
    let onSave: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var systemPrompt = ""
    @State private var selectedAgentTypes: Set<AgentTask.AgentType> = []
    @State private var tagsText = ""
    @State private var errorMessage: String?

    private var isEditing: Bool { editing != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L("personas.name")) {
                    TextField(L("personas.name"), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(editing?.isBuiltIn == true)
                }

                Section(L("personas.description")) {
                    TextField(L("personas.description"), text: $description)
                        .textFieldStyle(.roundedBorder)
                }

                Section(L("personas.systemPrompt")) {
                    ZStack(alignment: .topLeading) {
                        if systemPrompt.isEmpty {
                            Text("Enter the persona's system prompt...")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden)
                    }
                    .frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                }

                Section(L("personas.agentTypes")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 6) {
                        ForEach(AgentTask.AgentType.allCases, id: \.self) { type in
                            Toggle(type.rawValue.capitalized, isOn: Binding(
                                get: { selectedAgentTypes.contains(type) },
                                set: { isOn in
                                    if isOn { selectedAgentTypes.insert(type) }
                                    else { selectedAgentTypes.remove(type) }
                                }
                            ))
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }
                }

                Section(L("personas.tags")) {
                    TextField("architecture, design, security...", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                    Text("Comma-separated tags")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button(L("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? L("common.save") : L("personas.add")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || systemPrompt.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 520)
        .onAppear {
            if let p = editing {
                name = p.name
                description = p.description
                systemPrompt = p.systemPrompt
                selectedAgentTypes = Set(p.agentTypes)
                tagsText = p.tags.joined(separator: ", ")
            }
        }
    }

    private func save() {
        guard let db = appDatabase else { return }
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let agentTypes = Array(selectedAgentTypes).sorted { $0.rawValue < $1.rawValue }

        do {
            try db.dbQueue.write { dbConn in
                if var existing = editing {
                    existing.name = name
                    existing.description = description
                    existing.systemPrompt = systemPrompt
                    existing.agentTypes = agentTypes
                    existing.tags = tags
                    existing.updatedAt = Date()
                    try existing.update(dbConn)
                } else {
                    var persona = AgentPersona(
                        name: name,
                        description: description,
                        systemPrompt: systemPrompt,
                        agentTypes: agentTypes,
                        tags: tags
                    )
                    try persona.insert(dbConn)
                }
            }
            Task { await onSave() }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
