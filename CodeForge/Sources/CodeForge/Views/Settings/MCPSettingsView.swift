import SwiftUI
import GRDB

/// Settings view for managing MCP server configurations.
struct MCPSettingsView: View {
    let appDatabase: AppDatabase?
    @State private var store = MCPServerConfigStore()
    @State private var showAddSheet = false
    @State private var editingConfig: MCPServerConfig?

    var body: some View {
        Form {
            Section {
                if store.configs.isEmpty {
                    ContentUnavailableView(
                        "No MCP Servers",
                        systemImage: "server.rack",
                        description: Text("Add MCP servers that agents can use for external tool access")
                    )
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
            } header: {
                HStack {
                    Text("MCP Servers")
                    Spacer()
                    Button("Add Server", systemImage: "plus") {
                        showAddSheet = true
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
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

// MARK: - Row

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
