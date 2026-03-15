import SwiftUI
import GRDB

/// Settings view for issue tracking integrations (Linear, Jira).
struct IntegrationsSettingsView: View {
    let appDatabase: AppDatabase?

    @State private var configs: [IssueTrackingConfig] = []
    @State private var showingAddSheet = false
    @State private var editingConfig: IssueTrackingConfig?
    @State private var importingConfigId: UUID?
    @State private var importStatus: String?
    @State private var projects: [Project] = []

    var body: some View {
        Form {
            Section("Issue Tracking Integrations") {
                if configs.isEmpty {
                    Text("No integrations configured. Add a Linear or Jira integration to import issues.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(configs) { config in
                    configRow(config)
                }

                Button("Add Integration...") {
                    showingAddSheet = true
                }
            }

            Section {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Jira integration is coming soon")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let status = importStatus {
                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await loadData() }
        .sheet(isPresented: $showingAddSheet) {
            IntegrationConfigSheet(
                appDatabase: appDatabase,
                projects: projects,
                config: nil,
                onSave: { await loadData() }
            )
        }
        .sheet(item: $editingConfig) { config in
            IntegrationConfigSheet(
                appDatabase: appDatabase,
                projects: projects,
                config: config,
                onSave: { await loadData() }
            )
        }
    }

    @ViewBuilder
    private func configRow(_ config: IssueTrackingConfig) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.name)
                        .font(.subheadline.weight(.medium))
                    Text(config.provider.rawValue.capitalized)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(config.provider == .linear ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(config.provider == .linear ? .purple : .blue)
                    if !config.isEnabled {
                        Text("Disabled")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let lastSync = config.lastSyncAt {
                    Text("Last sync: \(lastSync, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if importingConfigId == config.id {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            } else if config.provider == .linear && config.isEnabled {
                Button("Import Now") {
                    Task { await importIssues(config: config) }
                }
                .controlSize(.small)
            }

            Button {
                editingConfig = config
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                Task { await deleteConfig(config) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private func loadData() async {
        guard let db = appDatabase else { return }
        do {
            configs = try await db.dbQueue.read { dbConn in
                try IssueTrackingConfig.fetchAll(dbConn)
            }
            projects = try await db.dbQueue.read { dbConn in
                try Project.fetchAll(dbConn)
            }
        } catch {
            // Non-fatal
        }
    }

    private func importIssues(config: IssueTrackingConfig) async {
        guard let db = appDatabase else { return }
        importingConfigId = config.id
        importStatus = nil

        do {
            let coordinator = IssueSyncCoordinator(dbQueue: db.dbQueue)
            let mappings = try await coordinator.importIssues(configId: config.id)
            importStatus = "Imported \(mappings.count) issues from \(config.name)"
            await loadData()
        } catch {
            importStatus = "Import failed: \(error.localizedDescription)"
        }

        importingConfigId = nil
    }

    private func deleteConfig(_ config: IssueTrackingConfig) async {
        guard let db = appDatabase else { return }
        do {
            _ = try await db.dbQueue.write { dbConn in
                try config.delete(dbConn)
            }
            await loadData()
        } catch {
            // Non-fatal
        }
    }
}

// MARK: - Config Sheet

private struct IntegrationConfigSheet: View {
    let appDatabase: AppDatabase?
    let projects: [Project]
    let config: IssueTrackingConfig?
    let onSave: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var provider: IssueTrackingConfig.Provider = .linear
    @State private var selectedProjectId: UUID?
    @State private var apiKey = ""
    @State private var teamId = ""
    @State private var isEnabled = true
    @State private var syncBackEnabled = false
    @State private var doneStateId = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(config == nil ? "Add Integration" : "Edit Integration")
                .font(.headline)
                .padding()

            Form {
                Picker("Provider", selection: $provider) {
                    Text("Linear").tag(IssueTrackingConfig.Provider.linear)
                    Text("Jira").tag(IssueTrackingConfig.Provider.jira)
                }

                if provider == .jira {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Jira integration is coming soon")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                Picker("Project", selection: $selectedProjectId) {
                    Text("Select a project...").tag(UUID?.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }

                if provider == .linear {
                    Section("Linear Configuration") {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        TextField("Team ID (optional)", text: $teamId)
                            .textFieldStyle(.roundedBorder)
                        TextField("Done State ID (for sync-back)", text: $doneStateId)
                            .textFieldStyle(.roundedBorder)
                        Text("Get API key from Linear → Settings → API")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Enabled", isOn: $isEnabled)
                Toggle("Sync status back on completion", isOn: $syncBackEnabled)

                if let error = errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(config == nil ? "Add" : "Save") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || selectedProjectId == nil || (provider == .linear && apiKey.isEmpty))
            }
            .padding()
        }
        .frame(width: 420, height: 480)
        .onAppear {
            if let config {
                name = config.name
                provider = config.provider
                selectedProjectId = config.projectId
                isEnabled = config.isEnabled
                syncBackEnabled = config.syncBackEnabled

                // Parse credentials
                if let data = config.credentialsJSON.data(using: .utf8),
                   let creds = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    apiKey = creds["apiKey"] ?? ""
                }

                // Parse config
                if let data = config.configJSON.data(using: .utf8),
                   let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    teamId = cfg["teamId"] as? String ?? ""
                    doneStateId = cfg["doneStateId"] as? String ?? ""
                }
            }
        }
    }

    private func save() async {
        guard let db = appDatabase, let projectId = selectedProjectId else { return }

        let credentialsJSON: String
        let configJSON: String

        if provider == .linear {
            credentialsJSON = "{\"apiKey\":\"\(apiKey)\"}"
            var cfgDict: [String: Any] = [:]
            if !teamId.isEmpty { cfgDict["teamId"] = teamId }
            if !doneStateId.isEmpty { cfgDict["doneStateId"] = doneStateId }
            cfgDict["stateFilter"] = ["Todo", "In Progress"]
            cfgDict["agentType"] = "coder"
            if let data = try? JSONSerialization.data(withJSONObject: cfgDict) {
                configJSON = String(data: data, encoding: .utf8) ?? "{}"
            } else {
                configJSON = "{}"
            }
        } else {
            credentialsJSON = "{}"
            configJSON = "{}"
        }

        do {
            try await db.dbQueue.write { dbConn in
                if var existing = config {
                    existing.name = name
                    existing.provider = provider
                    existing.projectId = projectId
                    existing.credentialsJSON = credentialsJSON
                    existing.configJSON = configJSON
                    existing.isEnabled = isEnabled
                    existing.syncBackEnabled = syncBackEnabled
                    existing.updatedAt = Date()
                    try existing.update(dbConn)
                } else {
                    var newConfig = IssueTrackingConfig(
                        projectId: projectId,
                        provider: provider,
                        name: name,
                        credentialsJSON: credentialsJSON,
                        configJSON: configJSON,
                        isEnabled: isEnabled,
                        syncBackEnabled: syncBackEnabled
                    )
                    try newConfig.insert(dbConn)
                }
            }
            await onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
