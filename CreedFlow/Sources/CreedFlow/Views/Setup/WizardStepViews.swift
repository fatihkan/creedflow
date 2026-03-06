import SwiftUI
import GRDB

// MARK: - Step 1: Environment Detection

struct WizardEnvironmentStep: View {
    let detector: EnvironmentDetector
    let installer: DependencyInstaller
    @Binding var claudePathOverride: String
    @Binding var codexPathOverride: String
    @Binding var geminiPathOverride: String
    @Binding var opencodePathOverride: String
    @Binding var openclawPathOverride: String
    @Binding var qwenPathOverride: String
    @Binding var ollamaPathOverride: String
    @Binding var lmstudioPathOverride: String
    @Binding var llamacppPathOverride: String
    @Binding var mlxPathOverride: String
    @Binding var selectedEditor: String
    @Binding var gitUserNameInput: String
    @Binding var gitUserEmailInput: String

    /// Check if Node.js (npm) is available for npm-based CLI installs
    private var hasNode: Bool {
        detector.findExecutable("npm") != nil
    }

    /// Check if Go is available for go install
    private var hasGo: Bool {
        detector.findExecutable("go") != nil
    }

    /// Check if Homebrew is available
    private var hasBrew: Bool {
        detector.findBrewPath() != nil
    }

    /// Check if Python 3 (pip3) is available
    private var hasPip3: Bool {
        detector.findExecutable("pip3") != nil
    }

    var body: some View {
        Form {
            Section("AI CLIs") {
                CLIDetectionRow(
                    label: "Claude CLI",
                    found: detector.claudeFound,
                    path: detector.claudePath,
                    version: detector.claudeVersion,
                    installing: detector.claudeInstalling,
                    installError: detector.claudeInstallError,
                    hasPrerequisite: hasNode,
                    prerequisiteName: "Node.js"
                ) {
                    Task { await detector.installCLI("claude") }
                }
                CLIPathOverrideRow(path: $claudePathOverride, placeholder: "Claude CLI custom path")

                Divider()

                CLIDetectionRow(
                    label: "Codex CLI",
                    found: detector.codexFound,
                    path: detector.codexPath,
                    version: detector.codexVersion,
                    installing: detector.codexInstalling,
                    installError: detector.codexInstallError,
                    hasPrerequisite: hasNode,
                    prerequisiteName: "Node.js"
                ) {
                    Task { await detector.installCLI("codex") }
                }
                CLIPathOverrideRow(path: $codexPathOverride, placeholder: "Codex CLI custom path")

                Divider()

                CLIDetectionRow(
                    label: "Gemini CLI",
                    found: detector.geminiFound,
                    path: detector.geminiPath,
                    version: detector.geminiVersion,
                    installing: detector.geminiInstalling,
                    installError: detector.geminiInstallError,
                    hasPrerequisite: hasNode,
                    prerequisiteName: "Node.js"
                ) {
                    Task { await detector.installCLI("gemini") }
                }
                CLIPathOverrideRow(path: $geminiPathOverride, placeholder: "Gemini CLI custom path")

                Divider()

                CLIDetectionRow(
                    label: "OpenCode",
                    found: detector.opencodeFound,
                    path: detector.opencodePath,
                    version: detector.opencodeVersion,
                    installing: detector.opencodeInstalling,
                    installError: detector.opencodeInstallError,
                    hasPrerequisite: hasGo,
                    prerequisiteName: "Go"
                ) {
                    Task { await detector.installCLI("opencode") }
                }
                CLIPathOverrideRow(path: $opencodePathOverride, placeholder: "OpenCode custom path")

                Divider()

                CLIDetectionRow(
                    label: "OpenClaw",
                    found: detector.openclawFound,
                    path: detector.openclawPath,
                    version: detector.openclawVersion,
                    installing: detector.openclawInstalling,
                    installError: detector.openclawInstallError,
                    hasPrerequisite: hasNode,
                    prerequisiteName: "Node.js"
                ) {
                    Task { await detector.installCLI("openclaw") }
                }
                CLIPathOverrideRow(path: $openclawPathOverride, placeholder: "OpenClaw custom path")

                Divider()

                CLIDetectionRow(
                    label: "Qwen Code",
                    found: detector.qwenFound,
                    path: detector.qwenPath,
                    version: detector.qwenVersion,
                    installing: detector.qwenInstalling,
                    installError: detector.qwenInstallError,
                    hasPrerequisite: hasNode,
                    prerequisiteName: "Node.js"
                ) {
                    Task { await detector.installCLI("qwen") }
                }
                CLIPathOverrideRow(path: $qwenPathOverride, placeholder: "Qwen Code custom path")
            }

            Section("Local LLMs (Optional)") {
                CLIDetectionRow(
                    label: "Ollama",
                    found: detector.ollamaFound,
                    path: detector.ollamaPath,
                    version: detector.ollamaVersion,
                    installing: detector.ollamaInstalling,
                    installError: detector.ollamaInstallError,
                    hasPrerequisite: hasBrew,
                    prerequisiteName: "Homebrew"
                ) {
                    Task { await detector.installCLI("ollama") }
                }
                CLIPathOverrideRow(path: $ollamaPathOverride, placeholder: "Ollama custom path")

                Divider()

                CLIDetectionRow(
                    label: "LM Studio",
                    found: detector.lmstudioFound,
                    path: detector.lmstudioPath,
                    version: detector.lmstudioVersion,
                    installing: detector.lmstudioInstalling,
                    installError: detector.lmstudioInstallError,
                    hasPrerequisite: hasBrew,
                    prerequisiteName: "Homebrew"
                ) {
                    Task { await detector.installCLI("lmstudio") }
                }
                CLIPathOverrideRow(path: $lmstudioPathOverride, placeholder: "LM Studio (lms) custom path")

                Divider()

                CLIDetectionRow(
                    label: "llama.cpp",
                    found: detector.llamacppFound,
                    path: detector.llamacppPath,
                    version: detector.llamacppVersion,
                    installing: detector.llamacppInstalling,
                    installError: detector.llamacppInstallError,
                    hasPrerequisite: hasBrew,
                    prerequisiteName: "Homebrew"
                ) {
                    Task { await detector.installCLI("llamacpp") }
                }
                CLIPathOverrideRow(path: $llamacppPathOverride, placeholder: "llama-cli custom path")

                Divider()

                CLIDetectionRow(
                    label: "MLX-LM",
                    found: detector.mlxFound,
                    path: detector.mlxPath,
                    version: "",
                    installing: detector.mlxInstalling,
                    installError: detector.mlxInstallError,
                    hasPrerequisite: hasPip3,
                    prerequisiteName: "Python 3"
                ) {
                    Task { await detector.installCLI("mlx") }
                }
                CLIPathOverrideRow(path: $mlxPathOverride, placeholder: "mlx_lm.generate custom path")
            }

            Section {
                Button {
                    Task {
                        await detector.detectAll(
                            claudeOverride: claudePathOverride,
                            codexOverride: codexPathOverride,
                            geminiOverride: geminiPathOverride,
                            opencodeOverride: opencodePathOverride,
                            openclawOverride: openclawPathOverride,
                            qwenOverride: qwenPathOverride,
                            ollamaOverride: ollamaPathOverride,
                            lmstudioOverride: lmstudioPathOverride,
                            llamacppOverride: llamacppPathOverride,
                            mlxOverride: mlxPathOverride
                        )
                    }
                } label: {
                    HStack(spacing: 4) {
                        if detector.isDetecting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh")
                    }
                }
                .disabled(detector.isDetecting)
            }

            Section("GitHub CLI") {
                DetectionRow(
                    label: "gh CLI",
                    found: detector.ghFound,
                    detail: detector.ghFound
                        ? "\(detector.ghPath) (\(detector.ghVersion))"
                        : "Not found — optional, needed for PR creation"
                )
            }

            Section("Git Configuration") {
                if detector.gitConfigured {
                    DetectionRow(label: "Git user.name", found: true, detail: detector.gitUserName)
                    DetectionRow(label: "Git user.email", found: true, detail: detector.gitUserEmail)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.forgeWarning)
                        Text("Git user not configured")
                            .font(.subheadline.weight(.medium))
                    }
                    TextField("Name", text: $gitUserNameInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("Email", text: $gitUserEmailInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Configure Git") {
                        Task {
                            await detector.configureGit(userName: gitUserNameInput, email: gitUserEmailInput)
                        }
                    }
                    .disabled(gitUserNameInput.isEmpty || gitUserEmailInput.isEmpty)
                }

                Text("CreedFlow uses a 3-branch strategy: dev \u{2192} staging \u{2192} main with feature branches per coder task.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Code Editors") {
                if detector.detectedEditors.isEmpty && detector.uninstalledEditors.isEmpty && !detector.isDetecting {
                    Text("No code editors found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detector.detectedEditors, id: \.command) { editor in
                        DetectionRow(
                            label: editor.name,
                            found: true,
                            detail: editor.path
                        )
                    }

                    ForEach(detector.uninstalledEditors, id: \.command) { editor in
                        HStack(spacing: 8) {
                            Image(systemName: "circle.dashed")
                                .foregroundStyle(.forgeNeutral)
                                .font(.body)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(editor.name)
                                    .font(.subheadline.weight(.medium))
                                Text("Not installed")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if detector.editorInstalling == editor.command {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else if hasBrew {
                                Button("Install") {
                                    Task { await detector.installEditor(editor.command) }
                                }
                                .controlSize(.small)
                            } else {
                                Text("Needs Homebrew")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let error = detector.editorInstallError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }

                if !detector.detectedEditors.isEmpty {
                    Picker("Preferred Editor", selection: $selectedEditor) {
                        Text("None").tag("")
                        ForEach(detector.detectedEditors, id: \.command) { editor in
                            Text(editor.name).tag(editor.command)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Step 2: Dependencies

struct WizardDependenciesStep: View {
    let installer: DependencyInstaller

    var body: some View {
        Form {
            Section("Package Manager") {
                HStack(spacing: 8) {
                    Image(systemName: installer.brewDetected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(installer.brewDetected ? .forgeSuccess : .forgeWarning)
                        .font(.body)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Homebrew")
                            .font(.subheadline.weight(.medium))
                        Text(installer.brewDetected ? installer.brewVersion : "Not found — required for installing dependencies")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !installer.brewDetected {
                        if installer.isInstallingBrew {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Button("Install") {
                                Task { await installer.installBrew() }
                            }
                            .controlSize(.small)
                        }
                    }
                }
                if installer.isInstallingBrew && !installer.brewInstallOutput.isEmpty {
                    Text(installer.brewInstallOutput.suffix(200))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let error = installer.brewInstallError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Section("System Dependencies") {
                if installer.isDetecting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                        Text("Detecting installed tools...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(installer.dependencies, id: \.id) { dep in
                        DependencyRow(dep: dep, brewAvailable: installer.brewDetected) {
                            Task { await installer.install(dep.id) }
                        }
                    }
                }
            }

            Section {
                HStack {
                    Button {
                        Task { await installer.detectAll() }
                    } label: {
                        HStack(spacing: 4) {
                            if installer.isDetecting {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh")
                        }
                    }
                    .disabled(installer.isDetecting || installer.anyInstalling)

                    Spacer()

                    if installer.missingCount > 0 && installer.brewDetected {
                        Button {
                            Task { await installer.installAllMissing() }
                        } label: {
                            HStack(spacing: 4) {
                                if installer.isInstallingAll {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                }
                                Text("Install All Missing (\(installer.missingCount))")
                            }
                        }
                        .disabled(installer.anyInstalling)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DependencyRow: View {
    let dep: SystemDependency
    let brewAvailable: Bool
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: dep.isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(dep.isInstalled ? .forgeSuccess : .forgeNeutral)
                    .font(.body)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dep.name)
                        .font(.subheadline.weight(.medium))
                    Text(dep.isInstalled ? dep.detectedVersion : dep.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if dep.isInstalling {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else if !dep.isInstalled && (brewAvailable || dep.customInstall != nil) {
                    Button("Install") { onInstall() }
                        .controlSize(.small)
                }
            }
            if dep.isInstalling && !dep.installOutput.isEmpty {
                Text(dep.installOutput.suffix(200))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 28)
            }
            if let error = dep.installError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.leading, 28)
            }
        }
    }
}

// MARK: - Step 3: Projects & Budget

struct WizardProjectsStep: View {
    @Binding var projectsBaseDir: String
    @Binding var maxConcurrency: Int
    @Binding var defaultBudget: Double

    var body: some View {
        Form {
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
                Text("Where CreedFlow creates project folders. Default: ~/CreedFlow/projects/")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Concurrency") {
                Stepper("Max Parallel Agents: \(maxConcurrency)", value: $maxConcurrency, in: 1...8)
                Text("How many AI agents can run simultaneously")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Budget section hidden for now
        }
        .formStyle(.grouped)
    }
}

// MARK: - Step 4: Integrations (Optional)

struct WizardIntegrationsStep: View {
    @Binding var telegramBotToken: String
    @Binding var telegramChatId: String

    @State private var isSendingTest = false
    @State private var testResult: TestResult?

    private enum TestResult {
        case success
        case error(String)
    }

    private var canTest: Bool {
        !telegramBotToken.isEmpty && !telegramChatId.isEmpty
    }

    var body: some View {
        Form {
            Section("Telegram Bot (Optional)") {
                SecureField("Bot Token", text: $telegramBotToken)
                    .textFieldStyle(.roundedBorder)
                TextField("Default Chat ID", text: $telegramChatId)
                    .textFieldStyle(.roundedBorder)
                Text("Get a bot token from @BotFather on Telegram. Skip if you don't need notifications.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if canTest {
                Section("Test Connection") {
                    HStack(spacing: 10) {
                        Button {
                            Task { await sendTestMessage() }
                        } label: {
                            HStack(spacing: 6) {
                                if isSendingTest {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text("Send Test Message")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.forgeAmber)
                        .disabled(isSendingTest)
                        .controlSize(.small)

                        if let testResult {
                            switch testResult {
                            case .success:
                                Label("Sent!", systemImage: "checkmark.circle.fill")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.forgeSuccess)
                            case .error(let message):
                                Label(message, systemImage: "xmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.forgeDanger)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: telegramBotToken) { _, _ in testResult = nil }
        .onChange(of: telegramChatId) { _, _ in testResult = nil }
    }

    private func sendTestMessage() async {
        isSendingTest = true
        defer { isSendingTest = false }

        let service = TelegramBotService()
        guard let chatId = Int64(telegramChatId) else {
            testResult = .error("Invalid Chat ID — must be a number")
            return
        }

        service.configure(token: telegramBotToken, chatId: chatId)
        do {
            try await service.sendMessage("CreedFlow test message — connection successful!")
            testResult = .success
        } catch {
            testResult = .error(error.localizedDescription)
        }
    }
}

// MARK: - Step 5: MCP Servers (Optional)

struct WizardMCPStep: View {
    let appDatabase: AppDatabase?
    let store: MCPServerConfigStore
    @State private var setupTemplate: MCPServerTemplate?

    /// Templates grouped by category for the wizard
    private var essentialTemplates: [MCPServerTemplate] {
        [.creedFlow, .filesystem, .github]
    }

    private var creativeTemplates: [MCPServerTemplate] {
        [.dalle, .figma, .stability, .elevenlabs, .runway, .heygen, .replicate, .leonardo]
    }

    private var otherTemplates: [MCPServerTemplate] {
        [.promptsChat]
    }

    /// Whether at least one creative MCP service is configured
    private var hasConfiguredCreativeService: Bool {
        let creativeIds = Set(creativeTemplates.map(\.id))
        return store.configs.contains { creativeIds.contains($0.name) }
    }

    var body: some View {
        Form {
            Section {
                Text("MCP servers extend agent capabilities with external tools. Configure the ones you need — you can always add more later in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Essential") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(essentialTemplates, id: \.id) { template in
                        wizardTemplateCard(template)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Creative AI Services") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(creativeTemplates, id: \.id) { template in
                        wizardTemplateCard(template)
                    }
                }
                .padding(.vertical, 4)

                if !hasConfiguredCreativeService {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.forgeWarning)
                            .font(.footnote)
                        Text("Content and image projects require at least one creative AI service. Configure an API key above to enable image/video generation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Other") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(otherTemplates, id: \.id) { template in
                        wizardTemplateCard(template)
                    }
                }
                .padding(.vertical, 4)
            }

            if !store.configs.isEmpty {
                Section("Configured (\(store.configs.count))") {
                    ForEach(store.configs, id: \.id) { config in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.forgeSuccess)
                                .font(.footnote)
                            Text(config.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button(role: .destructive) {
                                removeConfig(config)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.footnote)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $setupTemplate) { template in
            WizardMCPTemplateSetupSheet(appDatabase: appDatabase, template: template)
        }
    }

    private func wizardTemplateCard(_ template: MCPServerTemplate) -> some View {
        let isConfigured = store.configs.contains { $0.name == template.id }
        return Button {
            if isConfigured { return }
            if template.requiredInputs.isEmpty {
                installDirectly(template)
            } else {
                setupTemplate = template
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: template.icon)
                        .font(.title3)
                        .foregroundStyle(isConfigured ? .forgeSuccess : .forgeAmber)
                        .frame(width: 28, height: 28)
                    if isConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.forgeSuccess)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(template.displayName)
                    .font(.footnote.weight(.medium))
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isConfigured ? Color.forgeSuccess.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(isConfigured ? 0.7 : 1.0)
    }

    private func installDirectly(_ template: MCPServerTemplate) {
        guard let db = appDatabase else { return }
        var config = template.buildConfig(inputs: [:])
        try? db.dbQueue.write { dbConn in
            try config.insert(dbConn)
        }
    }

    private func removeConfig(_ config: MCPServerConfig) {
        guard let db = appDatabase else { return }
        _ = try? db.dbQueue.write { dbConn in
            try config.delete(dbConn)
        }
    }
}

/// Setup sheet for MCP templates that require input (API keys, paths)
private struct WizardMCPTemplateSetupSheet: View {
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
                ForEach(template.requiredInputs, id: \.id) { input in
                    Section(input.label) {
                        switch input.type {
                        case .path:
                            HStack {
                                TextField(input.placeholder, text: binding(for: input.id))
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseDirectories = true
                                    panel.canChooseFiles = true
                                    panel.allowsMultipleSelection = false
                                    if panel.runModal() == .OK, let url = panel.url {
                                        inputValues[input.id] = url.path
                                    }
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
                    .buttonStyle(.borderedProminent)
                    .tint(.forgeAmber)
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

    private func install() {
        guard let db = appDatabase else { return }
        var config = template.buildConfig(inputs: inputValues)
        try? db.dbQueue.write { dbConn in
            try config.insert(dbConn)
        }
        dismiss()
    }
}

// MARK: - Step 6: Summary

struct WizardSummaryStep: View {
    let detector: EnvironmentDetector
    let claudePathOverride: String
    let codexPathOverride: String
    let geminiPathOverride: String
    let opencodePathOverride: String
    let openclawPathOverride: String
    let qwenPathOverride: String
    let ollamaPathOverride: String
    let lmstudioPathOverride: String
    let llamacppPathOverride: String
    let mlxPathOverride: String
    let projectsBaseDir: String
    let maxConcurrency: Int
    let defaultBudget: Double
    let telegramConfigured: Bool
    let mcpConfigs: [MCPServerConfig]
    let selectedEditor: String

    private var editorDisplayName: String {
        detector.detectedEditors.first(where: { $0.command == selectedEditor })?.name ?? selectedEditor
    }

    private var effectiveClaudePath: String {
        if !claudePathOverride.isEmpty { return claudePathOverride }
        if detector.claudeFound { return detector.claudePath }
        return "Not configured"
    }

    private var effectiveCodexPath: String {
        if !codexPathOverride.isEmpty { return codexPathOverride }
        if detector.codexFound { return detector.codexPath }
        return "Not found"
    }

    private var effectiveGeminiPath: String {
        if !geminiPathOverride.isEmpty { return geminiPathOverride }
        if detector.geminiFound { return detector.geminiPath }
        return "Not found"
    }

    private var effectiveOpencodePath: String {
        if !opencodePathOverride.isEmpty { return opencodePathOverride }
        if detector.opencodeFound { return detector.opencodePath }
        return "Not found"
    }

    private var effectiveOpenclawPath: String {
        if !openclawPathOverride.isEmpty { return openclawPathOverride }
        if detector.openclawFound { return detector.openclawPath }
        return "Not found"
    }

    private var effectiveQwenPath: String {
        if !qwenPathOverride.isEmpty { return qwenPathOverride }
        if detector.qwenFound { return detector.qwenPath }
        return "Not found"
    }

    private var effectiveOllamaPath: String {
        if !ollamaPathOverride.isEmpty { return ollamaPathOverride }
        if detector.ollamaFound { return detector.ollamaPath }
        return "Not found"
    }

    private var effectiveLmstudioPath: String {
        if !lmstudioPathOverride.isEmpty { return lmstudioPathOverride }
        if detector.lmstudioFound { return detector.lmstudioPath }
        return "Not found"
    }

    private var effectiveLlamacppPath: String {
        if !llamacppPathOverride.isEmpty { return llamacppPathOverride }
        if detector.llamacppFound { return detector.llamacppPath }
        return "Not found"
    }

    private var effectiveMlxPath: String {
        if !mlxPathOverride.isEmpty { return mlxPathOverride }
        if detector.mlxFound { return detector.mlxPath }
        return "Not found"
    }

    var body: some View {
        Form {
            Section("AI CLIs") {
                SummaryRow(label: "Claude CLI", value: effectiveClaudePath, ok: detector.claudeFound || !claudePathOverride.isEmpty)
                SummaryRow(label: "Codex CLI", value: effectiveCodexPath, ok: detector.codexFound || !codexPathOverride.isEmpty)
                SummaryRow(label: "Gemini CLI", value: effectiveGeminiPath, ok: detector.geminiFound || !geminiPathOverride.isEmpty)
                SummaryRow(label: "OpenCode", value: effectiveOpencodePath, ok: detector.opencodeFound || !opencodePathOverride.isEmpty)
                SummaryRow(label: "OpenClaw", value: effectiveOpenclawPath, ok: detector.openclawFound || !openclawPathOverride.isEmpty)
                SummaryRow(label: "Qwen Code", value: effectiveQwenPath, ok: detector.qwenFound || !qwenPathOverride.isEmpty)
            }

            Section("Local LLMs") {
                SummaryRow(label: "Ollama", value: effectiveOllamaPath, ok: detector.ollamaFound || !ollamaPathOverride.isEmpty)
                SummaryRow(label: "LM Studio", value: effectiveLmstudioPath, ok: detector.lmstudioFound || !lmstudioPathOverride.isEmpty)
                SummaryRow(label: "llama.cpp", value: effectiveLlamacppPath, ok: detector.llamacppFound || !llamacppPathOverride.isEmpty)
                SummaryRow(label: "MLX-LM", value: effectiveMlxPath, ok: detector.mlxFound || !mlxPathOverride.isEmpty)
            }

            Section("Dev Tools") {
                SummaryRow(label: "gh CLI", value: detector.ghFound ? detector.ghPath : "Not found", ok: detector.ghFound)
                SummaryRow(label: "Git user", value: detector.gitConfigured ? "\(detector.gitUserName) <\(detector.gitUserEmail)>" : "Not configured", ok: detector.gitConfigured)
                SummaryRow(
                    label: "Code Editor",
                    value: selectedEditor.isEmpty ? "None" : editorDisplayName,
                    ok: !selectedEditor.isEmpty
                )
            }

            Section("Projects") {
                SummaryRow(label: "Projects directory", value: projectsBaseDir.isEmpty ? "~/CreedFlow/projects/" : projectsBaseDir, ok: true)
                SummaryRow(label: "Max concurrency", value: "\(maxConcurrency) agents", ok: true)
            }

            Section("Integrations") {
                SummaryRow(label: "Telegram", value: telegramConfigured ? "Configured" : "Skipped", ok: telegramConfigured)
            }

            Section("MCP Servers") {
                if mcpConfigs.isEmpty {
                    SummaryRow(label: "MCP Servers", value: "None configured", ok: false)
                } else {
                    ForEach(mcpConfigs, id: \.id) { config in
                        SummaryRow(label: config.name, value: config.command, ok: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Helper Views

private struct CLIPathOverrideRow: View {
    @Binding var path: String
    let placeholder: String

    var body: some View {
        HStack {
            TextField(placeholder, text: $path)
                .textFieldStyle(.roundedBorder)
                .font(.footnote)
            Button("Browse") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                if panel.runModal() == .OK, let url = panel.url {
                    path = url.path
                }
            }
            .controlSize(.small)
        }
    }
}

private struct CLIDetectionRow: View {
    let label: String
    let found: Bool
    let path: String
    let version: String
    let installing: Bool
    let installError: String?
    let hasPrerequisite: Bool
    let prerequisiteName: String
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(found ? .forgeSuccess : .forgeWarning)
                    .font(.body)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                    if found {
                        Text(version.isEmpty ? path : "\(path) (v\(version))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not found")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !found {
                    if installing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else if hasPrerequisite {
                        Button("Install") { onInstall() }
                            .controlSize(.small)
                    } else {
                        Text("Needs \(prerequisiteName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let error = installError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.leading, 28)
            }
        }
    }
}

private struct DetectionRow: View {
    let label: String
    let found: Bool
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(found ? .forgeSuccess : .forgeWarning)
                .font(.body)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(ok ? .forgeSuccess : .forgeNeutral)
                .font(.footnote)
            Text(label)
                .font(.subheadline)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
