import SwiftUI
import GRDB

public struct SettingsView: View {
    @Environment(\.appDatabase) private var appDatabase
    @AppStorage("claudePath") private var claudePath = ""
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("geminiPath") private var geminiPath = ""
    @AppStorage("maxConcurrency") private var maxConcurrency = 3
    @AppStorage("telegramBotToken") private var telegramBotToken = ""
    @AppStorage("telegramChatId") private var telegramChatId = ""
    @AppStorage("defaultMaxBudgetUSD") private var defaultMaxBudgetUSD = 5.0
    @AppStorage("projectsBaseDir") private var projectsBaseDir = ""
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = true
    @AppStorage("claudeEnabled") private var claudeEnabled = true
    @AppStorage("codexEnabled") private var codexEnabled = true
    @AppStorage("geminiEnabled") private var geminiEnabled = true
    @AppStorage("opencodePath") private var opencodePath = ""
    @AppStorage("opencodeEnabled") private var opencodeEnabled = true
    @AppStorage("openclawPath") private var openclawPath = ""
    @AppStorage("openclawEnabled") private var openclawEnabled = true
    @AppStorage("qwenPath") private var qwenPath = ""
    @AppStorage("qwenEnabled") private var qwenEnabled = true
    @AppStorage("ollamaPath") private var ollamaPath = ""
    @AppStorage("ollamaEnabled") private var ollamaEnabled = false
    @AppStorage("ollamaModel") private var ollamaModel = ""
    @AppStorage("lmstudioEnabled") private var lmstudioEnabled = false
    @AppStorage("lmstudioModel") private var lmstudioModel = ""
    @AppStorage("llamacppPath") private var llamacppPath = ""
    @AppStorage("llamacppEnabled") private var llamacppEnabled = false
    @AppStorage("llamacppModelPath") private var llamacppModelPath = ""
    @AppStorage("mlxPath") private var mlxPath = ""
    @AppStorage("mlxEnabled") private var mlxEnabled = false
    @AppStorage("mlxModel") private var mlxModel = ""
    @AppStorage("preferredEditor") private var preferredEditor = ""
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("fontSizePreference") private var fontSizePreference = "normal"

    // Admin API keys for real usage tracking
    @AppStorage("anthropicAdminAPIKey") private var anthropicAdminKey = ""
    @AppStorage("openaiAdminAPIKey") private var openaiAdminKey = ""

    // Usage limits
    @AppStorage("claude4hLimitUSD") private var claude4hLimit: Double = 5.0
    @AppStorage("claudeWeeklyLimitUSD") private var claudeWeeklyLimit: Double = 25.0
    @AppStorage("codex4hLimitUSD") private var codex4hLimit: Double = 5.0
    @AppStorage("codexWeeklyLimitUSD") private var codexWeeklyLimit: Double = 25.0
    @AppStorage("gemini4hLimitUSD") private var gemini4hLimit: Double = 5.0
    @AppStorage("geminiWeeklyLimitUSD") private var geminiWeeklyLimit: Double = 25.0

    @State private var claudeVersion = "Checking..."
    @State private var detectedEditors: [(name: String, command: String, path: String)] = []
    @State private var codexVersion = "Checking..."
    @State private var geminiVersion = "Checking..."
    @State private var opencodeVersion = "Checking..."
    @State private var openclawVersion = "Checking..."
    @State private var qwenVersion = "Checking..."
    @State private var ollamaVersion = "Checking..."
    @State private var lmstudioVersion = "Checking..."
    @State private var llamacppVersion = "Checking..."
    @State private var mlxVersion = "Checking..."
    @State private var ghVersion = "Checking..."
    @State private var backendHealthStatus: [CLIBackendType: HealthEvent.HealthStatus] = [:]

    // Git & Dependencies
    @State private var gitDetector = EnvironmentDetector()
    @State private var depInstaller = DependencyInstaller()
    @State private var gitNameField = ""
    @State private var gitEmailField = ""
    @State private var isConfiguringGit = false

    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            aiCLIsTab
                .tabItem { Label("AI CLIs", systemImage: "brain") }

            gitAndToolsTab
                .tabItem { Label("Git & Tools", systemImage: "arrow.triangle.branch") }

            telegramTab
                .tabItem { Label("Telegram", systemImage: "paperplane") }

            databaseTab
                .tabItem { Label("Database", systemImage: "cylinder") }

            MCPSettingsView(appDatabase: appDatabase)
                .tabItem { Label("MCP", systemImage: "server.rack") }
        }
        .frame(width: 600, height: 640)
        .task {
            await checkToolVersions()
            await detectEditors()
            await gitDetector.detectAll()
            await depInstaller.detectAll()
            gitNameField = gitDetector.gitUserName
            gitEmailField = gitDetector.gitUserEmail
            await loadBackendHealthStatus()
        }
        .onAppear {
            applyAppearance(appearanceMode)
        }
    }

    private func applyAppearance(_ mode: String) {
        let appearance: NSAppearance?
        switch mode {
        case "light": appearance = NSAppearance(named: .aqua)
        case "dark": appearance = NSAppearance(named: .darkAqua)
        default: appearance = nil // system default
        }
        NSApp.appearance = appearance
    }

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    Label("System", systemImage: "laptopcomputer").tag("system")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceMode) { _, newValue in
                    applyAppearance(newValue)
                }

                Picker("Text Size", selection: $fontSizePreference) {
                    Text("Small").tag("small")
                    Text("Normal").tag("normal")
                    Text("Large").tag("large")
                    Text("X-Large").tag("xl")
                }
                .pickerStyle(.segmented)
            }

            Section("Concurrency") {
                Stepper("Max Parallel Agents: \(maxConcurrency)", value: $maxConcurrency, in: 1...8)
            }

            Section("Projects Directory") {
                HStack {
                    TextField("Base directory", text: $projectsBaseDir)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url {
                            projectsBaseDir = url.path
                        }
                    }
                }
                Text("Default: ~/CreedFlow/projects/")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Budget section hidden for now

            Section("Code Editor") {
                Picker("Preferred Editor", selection: $preferredEditor) {
                    Text("None").tag("")
                    ForEach(detectedEditors, id: \.command) { editor in
                        Text("\(editor.name) (\(editor.command))").tag(editor.command)
                    }
                }
                if detectedEditors.isEmpty {
                    Text("No editors detected. Install one from the Git & Tools tab.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Used for \"Open in Editor\" buttons throughout the app")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Setup") {
                Button("Re-run Setup Wizard") {
                    hasCompletedSetup = false
                }
                Text("Reset and walk through the initial setup wizard again")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var aiCLIsTab: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $claudeEnabled)
                CLISettingsRow(label: "Claude CLI Path", path: $claudePath, version: claudeVersion, enabled: claudeEnabled)
                if claudeEnabled {
                    UsageLimitFields(limit4h: $claude4hLimit, limitWeek: $claudeWeeklyLimit)
                    SecureField("Admin API Key (for usage tracking)", text: $anthropicAdminKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Get from console.anthropic.com \u{2192} Settings \u{2192} Admin Keys (sk-ant-admin...)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                backendSectionHeader("Claude CLI", type: .claude, enabled: claudeEnabled)
            }

            Section {
                Toggle("Enabled", isOn: $codexEnabled)
                CLISettingsRow(label: "Codex CLI Path", path: $codexPath, version: codexVersion, enabled: codexEnabled)
                if codexEnabled {
                    UsageLimitFields(limit4h: $codex4hLimit, limitWeek: $codexWeeklyLimit)
                    SecureField("Admin API Key (for usage tracking)", text: $openaiAdminKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Get from platform.openai.com \u{2192} Settings \u{2192} Admin Keys")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Install: npm install -g @openai/codex")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                backendSectionHeader("Codex CLI", type: .codex, enabled: codexEnabled)
            }

            Section {
                Toggle("Enabled", isOn: $geminiEnabled)
                CLISettingsRow(label: "Gemini CLI Path", path: $geminiPath, version: geminiVersion, enabled: geminiEnabled)
                if geminiEnabled {
                    UsageLimitFields(limit4h: $gemini4hLimit, limitWeek: $geminiWeeklyLimit)
                }
                Text("Install: npm install -g @google/gemini-cli")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                backendSectionHeader("Gemini CLI", type: .gemini, enabled: geminiEnabled)
            }

            Section {
                Toggle("Enabled", isOn: $opencodeEnabled)
                CLISettingsRow(label: "OpenCode Path", path: $opencodePath, version: opencodeVersion, enabled: opencodeEnabled)
                Text("Install: go install github.com/opencode-ai/opencode@latest")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                backendSectionHeader("OpenCode", type: .opencode, enabled: opencodeEnabled)
            }

            Section {
                Toggle("Enabled", isOn: $openclawEnabled)
                CLISettingsRow(label: "OpenClaw Path", path: $openclawPath, version: openclawVersion, enabled: openclawEnabled)
                Text("Install: npm install -g openclaw@latest")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                backendSectionHeader("OpenClaw", type: .openclaw, enabled: openclawEnabled)
            }

            Section {
                Toggle("Enabled", isOn: $qwenEnabled)
                CLISettingsRow(label: "Qwen Code Path", path: $qwenPath, version: qwenVersion, enabled: qwenEnabled)
                Text("Install: npm install -g @qwen-code/qwen-code@latest")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("Qwen Code")
                    if qwenEnabled {
                        Text("Active").font(.caption).foregroundStyle(.green)
                    } else {
                        Text("Disabled").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("Local LLMs")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enabled", isOn: $ollamaEnabled)
                CLISettingsRow(label: "Ollama Path", path: $ollamaPath, version: ollamaVersion, enabled: ollamaEnabled)
                TextField("Model (e.g. llama3.2)", text: $ollamaModel)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!ollamaEnabled)
                Text("Install: brew install ollama")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                backendSectionHeader("Ollama", type: .ollama, enabled: ollamaEnabled)
            }

            Section {
                Toggle("Enabled", isOn: $lmstudioEnabled)
                TextField("Model (e.g. default)", text: $lmstudioModel)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!lmstudioEnabled)
                Text("Install LM Studio from lmstudio.ai — runs on localhost:1234")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                backendSectionHeader("LM Studio", type: .lmstudio, enabled: lmstudioEnabled)
            }

            Section {
                Toggle("Enabled", isOn: $llamacppEnabled)
                CLISettingsRow(label: "llama-cli Path", path: $llamacppPath, version: llamacppVersion, enabled: llamacppEnabled)
                HStack {
                    TextField("GGUF Model Path", text: $llamacppModelPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!llamacppEnabled)
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowedContentTypes = [.data]
                        if panel.runModal() == .OK, let url = panel.url {
                            llamacppModelPath = url.path
                        }
                    }
                    .disabled(!llamacppEnabled)
                }
                Text("Install: brew install llama.cpp — requires a GGUF model file")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                backendSectionHeader("llama.cpp", type: .llamacpp, enabled: llamacppEnabled)
            }

            Section {
                Toggle("Enabled", isOn: $mlxEnabled)
                CLISettingsRow(label: "mlx_lm.generate Path", path: $mlxPath, version: mlxVersion, enabled: mlxEnabled)
                TextField("Model (e.g. mlx-community/Llama-3.2-3B-Instruct-4bit)", text: $mlxModel)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!mlxEnabled)
                Text("Install: pip install mlx-lm — Apple Silicon only")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                backendSectionHeader("MLX-LM", type: .mlx, enabled: mlxEnabled)
            }

            AgentBackendPreferencesSection()

            Section("Dev Tools") {
                LabeledContent("gh CLI Version", value: ghVersion)
            }

            Section {
                Button("Verify All Installations") {
                    Task { await checkToolVersions() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var gitAndToolsTab: some View {
        Form {
            Section("Git User") {
                HStack(spacing: 8) {
                    Image(systemName: gitDetector.gitConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(gitDetector.gitConfigured ? .forgeSuccess : .forgeWarning)
                    Text(gitDetector.gitConfigured ? "Configured" : "Not configured")
                        .font(.subheadline.weight(.medium))
                }
                TextField("user.name", text: $gitNameField)
                    .textFieldStyle(.roundedBorder)
                TextField("user.email", text: $gitEmailField)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button {
                        isConfiguringGit = true
                        Task {
                            await gitDetector.configureGit(userName: gitNameField, email: gitEmailField)
                            isConfiguringGit = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isConfiguringGit {
                                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                            }
                            Text("Save Git Config")
                        }
                    }
                    .disabled(gitNameField.isEmpty || gitEmailField.isEmpty || isConfiguringGit)
                    Spacer()
                    Button("Refresh") {
                        Task {
                            await gitDetector.detectAll()
                            gitNameField = gitDetector.gitUserName
                            gitEmailField = gitDetector.gitUserEmail
                        }
                    }
                }
            }

            Section("Branching Strategy") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CreedFlow uses a 3-branch strategy for managed projects:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        branchBadge("dev", color: .forgeInfo)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                        branchBadge("staging", color: .forgeWarning)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                        branchBadge("main", color: .forgeSuccess)
                    }
                    Text("Feature branches are created from dev. PRs auto-merge on review pass. Staging deploys promote to main.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("GitHub CLI") {
                LabeledContent("gh Version", value: ghVersion)
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: depInstaller.brewDetected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(depInstaller.brewDetected ? .forgeSuccess : .forgeWarning)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Homebrew")
                            .font(.subheadline.weight(.medium))
                        Text(depInstaller.brewDetected ? depInstaller.brewVersion : "Not found")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !depInstaller.brewDetected {
                        if depInstaller.isInstallingBrew {
                            ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                        } else {
                            Button("Install") {
                                Task { await depInstaller.installBrew() }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Package Manager")
            }

            Section {
                if depInstaller.isDetecting {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                        Text("Detecting...").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(depInstaller.dependencies) { dep in
                        HStack(spacing: 8) {
                            Image(systemName: dep.isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(dep.isInstalled ? .forgeSuccess : .forgeNeutral)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dep.name).font(.subheadline.weight(.medium))
                                Text(dep.isInstalled ? dep.detectedVersion : dep.description)
                                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if dep.isInstalling {
                                ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                            } else if !dep.isInstalled && (depInstaller.brewDetected || dep.customInstall != nil) {
                                Button("Install") {
                                    Task { await depInstaller.install(dep.id) }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }

                HStack {
                    Button {
                        Task { await depInstaller.detectAll() }
                    } label: {
                        HStack(spacing: 4) {
                            if depInstaller.isDetecting {
                                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh")
                        }
                    }
                    .disabled(depInstaller.isDetecting || depInstaller.anyInstalling)
                    Spacer()
                    if depInstaller.missingCount > 0 && depInstaller.brewDetected {
                        Button {
                            Task { await depInstaller.installAllMissing() }
                        } label: {
                            Text("Install All Missing (\(depInstaller.missingCount))")
                        }
                        .disabled(depInstaller.anyInstalling)
                    }
                }
            } header: {
                Text("System Dependencies")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Database Tab

    private var databaseTab: some View {
        Form {
            if let db = appDatabase {
                let dbPath = db.dbQueue.path ?? ""
                let service = DatabaseMaintenanceService(dbQueue: db.dbQueue, databasePath: dbPath)

                Section("Database Info") {
                    let size = service.databaseFileSize()
                    LabeledContent("File Size", value: DatabaseMaintenanceService.formatSize(size))

                    if let counts = try? service.tableCounts() {
                        DisclosureGroup("Tables (\(counts.count))") {
                            ForEach(counts, id: \.table) { item in
                                LabeledContent(item.table, value: "\(item.count) rows")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                    }
                }

                Section("Maintenance") {
                    Button("Vacuum Database") {
                        Task {
                            try? await service.vacuum()
                        }
                    }
                    .help("Compact the database file to reclaim unused space")

                    Button("Backup Database...") {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "creedflow-backup.sqlite"
                        panel.title = "Save Database Backup"
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        Task {
                            try? await service.backup(to: url)
                        }
                    }
                    .help("Save a copy of the database to a file")

                    Button("Prune Old Logs (> 30 days)") {
                        Task {
                            _ = try? await service.pruneLogs(olderThanDays: 30)
                        }
                    }
                    .help("Delete agent logs older than 30 days")
                }

                if let result = service.lastResult {
                    Section {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Database not available")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func backendSectionHeader(_ label: String, type: CLIBackendType, enabled: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
            if enabled {
                let status = backendHealthStatus[type] ?? .unknown
                Circle()
                    .fill(status.indicatorColor)
                    .frame(width: 7, height: 7)
                Text("Active").font(.caption).foregroundStyle(.green)
            } else {
                Text("Disabled").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func branchBadge(_ name: String, color: Color) -> some View {
        Text(name)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }

    private var telegramTab: some View {
        Form {
            Section("Telegram Bot") {
                SecureField("Bot Token", text: $telegramBotToken)
                    .textFieldStyle(.roundedBorder)
                TextField("Default Chat ID", text: $telegramChatId)
                    .textFieldStyle(.roundedBorder)
                Text("Get a bot token from @BotFather on Telegram")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func checkToolVersions() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Check Claude
        let resolvedClaudePath = claudePath.isEmpty ? "\(home)/.local/bin/claude" : claudePath
        claudeVersion = await Self.checkCLIVersion(at: resolvedClaudePath)

        // Check Codex
        let resolvedCodexPath = codexPath.isEmpty ? "/usr/local/bin/codex" : codexPath
        codexVersion = await Self.checkCLIVersion(at: resolvedCodexPath)

        // Check Gemini
        let resolvedGeminiPath = geminiPath.isEmpty ? "/usr/local/bin/gemini" : geminiPath
        geminiVersion = await Self.checkCLIVersion(at: resolvedGeminiPath)

        // Check OpenCode
        let resolvedOpencodePath = opencodePath.isEmpty ? "/usr/local/bin/opencode" : opencodePath
        opencodeVersion = await Self.checkCLIVersion(at: resolvedOpencodePath)

        // Check OpenClaw
        let resolvedOpenclawPath = openclawPath.isEmpty ? "/usr/local/bin/openclaw" : openclawPath
        openclawVersion = await Self.checkCLIVersion(at: resolvedOpenclawPath)

        // Check Qwen Code
        let resolvedQwenPath = qwenPath.isEmpty ? "/usr/local/bin/qwen" : qwenPath
        qwenVersion = await Self.checkCLIVersion(at: resolvedQwenPath)

        // Check Ollama
        let resolvedOllamaPath = ollamaPath.isEmpty ? "/usr/local/bin/ollama" : ollamaPath
        ollamaVersion = await Self.checkCLIVersion(at: resolvedOllamaPath)

        // Check LM Studio (lms CLI)
        lmstudioVersion = await Self.checkCLIVersion(at: "/usr/local/bin/lms")

        // Check llama.cpp
        let resolvedLlamacppPath = llamacppPath.isEmpty ? "/opt/homebrew/bin/llama-cli" : llamacppPath
        llamacppVersion = await Self.checkCLIVersion(at: resolvedLlamacppPath)

        // Check MLX
        let resolvedMlxPath = mlxPath.isEmpty ? "\(home)/.local/bin/mlx_lm.generate" : mlxPath
        mlxVersion = await Self.checkCLIVersion(at: resolvedMlxPath, args: ["--help"])

        // Check gh
        ghVersion = await Self.checkCLIVersion(at: "/usr/local/bin/gh")
    }

    private func detectEditors() async {
        let detector = EnvironmentDetector()
        await detector.detectAll()
        detectedEditors = detector.detectedEditors
    }

    private func loadBackendHealthStatus() async {
        guard let db = appDatabase else { return }
        do {
            let events = try await db.dbQueue.read { dbConn in
                // Get the latest health event per backend
                try HealthEvent
                    .filter(Column("targetType") == HealthEvent.TargetType.backend.rawValue)
                    .order(Column("checkedAt").desc)
                    .fetchAll(dbConn)
            }
            // Take the latest event per backend name
            var statusMap: [CLIBackendType: HealthEvent.HealthStatus] = [:]
            for event in events {
                if let type = CLIBackendType(rawValue: event.targetName), statusMap[type] == nil {
                    statusMap[type] = event.status
                }
            }
            backendHealthStatus = statusMap
        } catch {
            // Non-fatal — status dots will show unknown/gray
        }
    }

    private static func checkCLIVersion(at path: String, args: [String] = ["--version"]) async -> String {
        do {
            let output = try await Process.run(path, arguments: args)
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? ""
        } catch {
            return "Not found"
        }
    }
}

// MARK: - CLI Settings Row

// MARK: - Usage Limit Fields

private struct UsageLimitFields: View {
    @Binding var limit4h: Double
    @Binding var limitWeek: Double

    var body: some View {
        GroupBox("Usage Limits") {
            HStack {
                Text("4-hour limit ($)")
                    .font(.subheadline)
                Spacer()
                TextField("", value: $limit4h, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Weekly limit ($)")
                    .font(.subheadline)
                Spacer()
                TextField("", value: $limitWeek, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(.subheadline)
    }
}

// MARK: - CLI Settings Row

private struct CLISettingsRow: View {
    let label: String
    @Binding var path: String
    let version: String
    var enabled: Bool = true

    var body: some View {
        HStack {
            TextField(label, text: $path)
                .textFieldStyle(.roundedBorder)
                .disabled(!enabled)
            Button("Browse") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                if panel.runModal() == .OK, let url = panel.url {
                    path = url.path
                }
            }
            .disabled(!enabled)
        }
        LabeledContent("Version", value: version)
    }
}
