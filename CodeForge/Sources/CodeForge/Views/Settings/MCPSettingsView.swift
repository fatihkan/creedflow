import SwiftUI
import GRDB

/// Settings view for managing MCP server configurations.
struct MCPSettingsView: View {
    let appDatabase: AppDatabase?
    @State private var store = MCPServerConfigStore()
    @State private var showAddSheet = false
    @State private var editingConfig: MCPServerConfig?
    @State private var setupTemplate: MCPServerTemplate?

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Settings")
            Divider()

            Form {
                templateSection
                configuredServersSection
                manualAddSection
            }
            .formStyle(.grouped)
        }
        .onAppear {
            if let db = appDatabase {
                store.observe(in: db.dbQueue)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            MCPServerEditSheet(appDatabase: appDatabase)
        }
        .sheet(item: $editingConfig) { config in
            MCPServerEditSheet(appDatabase: appDatabase, existing: config)
        }
        .sheet(item: $setupTemplate) { template in
            MCPTemplateSetupSheet(appDatabase: appDatabase, template: template)
        }
    }

    // MARK: - Quick Setup Templates

    private var templateSection: some View {
        Section("Quick Setup") {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(MCPServerTemplate.all) { template in
                    let isConfigured = store.configs.contains { $0.name == template.id }
                    MCPTemplateCard(
                        template: template,
                        isConfigured: isConfigured,
                        onTap: {
                            if template.requiredInputs.isEmpty {
                                installTemplateDirectly(template)
                            } else {
                                setupTemplate = template
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Configured Servers

    private var configuredServersSection: some View {
        Section("Configured Servers") {
            if store.configs.isEmpty {
                Text("No servers configured yet. Use Quick Setup above or add manually.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(store.configs) { config in
                    MCPServerRow(
                        config: config,
                        onToggle: { toggleEnabled(config) },
                        onEdit: { editingConfig = config },
                        onDelete: { delete(config) }
                    )
                }
            }
        }
    }

    // MARK: - Manual Add

    private var manualAddSection: some View {
        Section {
            Button {
                showAddSheet = true
            } label: {
                Label("Add Server Manually", systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Actions

    private func installTemplateDirectly(_ template: MCPServerTemplate) {
        guard let db = appDatabase else { return }
        var config = template.buildConfig(inputs: [:])
        try? db.dbQueue.write { dbConn in
            try config.insert(dbConn)
        }
    }

    private func toggleEnabled(_ config: MCPServerConfig) {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            var updated = config
            updated.isEnabled.toggle()
            updated.updatedAt = Date()
            try updated.update(dbConn)
        }
    }

    private func delete(_ config: MCPServerConfig) {
        guard let db = appDatabase else { return }
        _ = try? db.dbQueue.write { dbConn in
            try config.delete(dbConn)
        }
    }
}

// MARK: - Template Card

private struct MCPTemplateCard: View {
    let template: MCPServerTemplate
    let isConfigured: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: template.icon)
                        .font(.title2)
                        .foregroundStyle(isConfigured ? .forgeSuccess : .forgeAmber)
                        .frame(width: 36, height: 36)
                    if isConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.forgeSuccess)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(template.displayName)
                    .font(.subheadline.weight(.medium))
                Text(template.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isConfigured ? Color.forgeSuccess.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template Setup Sheet

private struct MCPTemplateSetupSheet: View {
    let appDatabase: AppDatabase?
    let template: MCPServerTemplate
    @Environment(\.dismiss) private var dismiss
    @State private var inputValues: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: template.icon)
                    .font(.largeTitle)
                    .foregroundStyle(Color.forgeAmber)
                Text("Setup \(template.displayName)")
                    .font(.headline)
                Text(template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Form {
                ForEach(template.requiredInputs) { input in
                    Section(input.label) {
                        switch input.type {
                        case .path:
                            HStack {
                                TextField(input.placeholder, text: binding(for: input.id))
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse") {
                                    pickPath(for: input.id)
                                }
                            }
                        case .secret:
                            SecureField(input.placeholder, text: binding(for: input.id))
                                .textFieldStyle(.roundedBorder)
                        case .text:
                            TextField(input.placeholder, text: binding(for: input.id))
                                .textFieldStyle(.roundedBorder)
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
                Button("Install") { install() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!allInputsFilled)
            }
            .padding()
        }
        .frame(width: 420, height: 320)
    }

    private var allInputsFilled: Bool {
        template.requiredInputs.allSatisfy { input in
            guard let value = inputValues[input.id] else { return false }
            return !value.isEmpty
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { inputValues[key, default: ""] },
            set: { inputValues[key] = $0 }
        )
    }

    private func pickPath(for inputId: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            inputValues[inputId] = url.path
        }
    }

    private func install() {
        guard let db = appDatabase else { return }
        var config = template.buildConfig(inputs: inputValues)
        try? db.dbQueue.write { dbConn in
            try config.insert(dbConn)
        }
        dismiss()
    }
}

// MARK: - Server Row

private struct MCPServerRow: View {
    let config: MCPServerConfig
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: .init(get: { config.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.headline)
                Text(config.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Edit", systemImage: "pencil") { onEdit() }
                .buttonStyle(.borderless)
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Edit Sheet

private struct MCPServerEditSheet: View {
    let appDatabase: AppDatabase?
    let existing: MCPServerConfig?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var command = ""
    @State private var argumentsText = ""
    @State private var envVarsText = ""

    init(appDatabase: AppDatabase?, existing: MCPServerConfig? = nil) {
        self.appDatabase = appDatabase
        self.existing = existing
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Server Info") {
                    TextField("Name (unique identifier)", text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("Command (executable path)", text: $command)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Arguments (one per line)") {
                    TextEditor(text: $argumentsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                }

                Section("Environment Variables (KEY=VALUE, one per line)") {
                    TextEditor(text: $envVarsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(existing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || command.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
        .onAppear {
            if let existing {
                name = existing.name
                command = existing.command
                argumentsText = existing.decodedArguments.joined(separator: "\n")
                let envPairs = existing.decodedEnvironmentVars.map { "\($0.key)=\($0.value)" }
                envVarsText = envPairs.joined(separator: "\n")
            }
        }
    }

    private func save() {
        guard let db = appDatabase else { return }
        let args = argumentsText.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        var envVars: [String: String] = [:]
        for line in envVarsText.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                envVars[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }

        try? db.dbQueue.write { dbConn in
            if var config = existing {
                config.name = name
                config.command = command
                config.arguments = (try? JSONEncoder().encode(args)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                config.environmentVars = (try? JSONEncoder().encode(envVars)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                config.updatedAt = Date()
                try config.update(dbConn)
            } else {
                var config = MCPServerConfig(
                    name: name,
                    command: command,
                    arguments: args,
                    environmentVars: envVars
                )
                try config.insert(dbConn)
            }
        }
        dismiss()
    }
}

// MARK: - Equatable for sheet(item:)

extension MCPServerTemplate: Equatable {
    static func == (lhs: MCPServerTemplate, rhs: MCPServerTemplate) -> Bool {
        lhs.id == rhs.id
    }
}
