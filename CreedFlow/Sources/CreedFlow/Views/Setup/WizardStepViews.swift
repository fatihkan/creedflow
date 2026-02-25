import SwiftUI
import GRDB

// MARK: - Step 1: Environment Detection

struct WizardEnvironmentStep: View {
    let detector: EnvironmentDetector
    @Binding var claudePathOverride: String
    @Binding var codexPathOverride: String
    @Binding var geminiPathOverride: String
    @Binding var opencodePathOverride: String
    @Binding var ollamaPathOverride: String
    @Binding var lmstudioPathOverride: String
    @Binding var llamacppPathOverride: String
    @Binding var mlxPathOverride: String

    var body: some View {
        Form {
            Section("AI CLIs") {
                DetectionRow(
                    label: "Claude CLI",
                    found: detector.claudeFound,
                    detail: detector.claudeFound
                        ? "\(detector.claudePath) (v\(detector.claudeVersion))"
                        : "Not found in common locations"
                )
                CLIPathOverrideRow(path: $claudePathOverride, placeholder: "Claude CLI custom path")

                Divider()

                DetectionRow(
                    label: "Codex CLI",
                    found: detector.codexFound,
                    detail: detector.codexFound
                        ? "\(detector.codexPath) (v\(detector.codexVersion))"
                        : "Not found — optional (npm i -g @openai/codex)"
                )
                CLIPathOverrideRow(path: $codexPathOverride, placeholder: "Codex CLI custom path")

                Divider()

                DetectionRow(
                    label: "Gemini CLI",
                    found: detector.geminiFound,
                    detail: detector.geminiFound
                        ? "\(detector.geminiPath) (v\(detector.geminiVersion))"
                        : "Not found — optional (npm i -g @anthropic-ai/gemini-cli)"
                )
                CLIPathOverrideRow(path: $geminiPathOverride, placeholder: "Gemini CLI custom path")

                Divider()

                DetectionRow(
                    label: "OpenCode",
                    found: detector.opencodeFound,
                    detail: detector.opencodeFound
                        ? "\(detector.opencodePath) (v\(detector.opencodeVersion))"
                        : "Not found — optional (go install github.com/opencode-ai/opencode@latest)"
                )
                CLIPathOverrideRow(path: $opencodePathOverride, placeholder: "OpenCode custom path")
            }

            Section("Local LLMs (Optional)") {
                DetectionRow(
                    label: "Ollama",
                    found: detector.ollamaFound,
                    detail: detector.ollamaFound
                        ? "\(detector.ollamaPath) (v\(detector.ollamaVersion))"
                        : "Not found — optional (brew install ollama)"
                )
                CLIPathOverrideRow(path: $ollamaPathOverride, placeholder: "Ollama custom path")

                Divider()

                DetectionRow(
                    label: "LM Studio",
                    found: detector.lmstudioFound,
                    detail: detector.lmstudioFound
                        ? "\(detector.lmstudioPath) (v\(detector.lmstudioVersion))"
                        : "Not found — optional (lmstudio.ai)"
                )
                CLIPathOverrideRow(path: $lmstudioPathOverride, placeholder: "LM Studio (lms) custom path")

                Divider()

                DetectionRow(
                    label: "llama.cpp",
                    found: detector.llamacppFound,
                    detail: detector.llamacppFound
                        ? "\(detector.llamacppPath) (v\(detector.llamacppVersion))"
                        : "Not found — optional (brew install llama.cpp)"
                )
                CLIPathOverrideRow(path: $llamacppPathOverride, placeholder: "llama-cli custom path")

                Divider()

                DetectionRow(
                    label: "MLX-LM",
                    found: detector.mlxFound,
                    detail: detector.mlxFound
                        ? "\(detector.mlxPath)"
                        : "Not found — optional (pip install mlx-lm)"
                )
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
                DetectionRow(
                    label: "Git user.name",
                    found: detector.gitConfigured,
                    detail: detector.gitConfigured
                        ? detector.gitUserName
                        : "Not configured"
                )
                DetectionRow(
                    label: "Git user.email",
                    found: !detector.gitUserEmail.isEmpty,
                    detail: !detector.gitUserEmail.isEmpty
                        ? detector.gitUserEmail
                        : "Not configured"
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Step 2: Projects & Budget

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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Concurrency") {
                Stepper("Max Parallel Agents: \(maxConcurrency)", value: $maxConcurrency, in: 1...8)
                Text("How many AI agents can run simultaneously")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Budget section hidden for now
        }
        .formStyle(.grouped)
    }
}

// MARK: - Step 3: Integrations (Optional)

struct WizardIntegrationsStep: View {
    @Binding var telegramBotToken: String
    @Binding var telegramChatId: String

    var body: some View {
        Form {
            Section("Telegram Bot (Optional)") {
                SecureField("Bot Token", text: $telegramBotToken)
                    .textFieldStyle(.roundedBorder)
                TextField("Default Chat ID", text: $telegramChatId)
                    .textFieldStyle(.roundedBorder)
                Text("Get a bot token from @BotFather on Telegram. Skip if you don't need notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Step 4: MCP Servers (Optional)

struct WizardMCPStep: View {
    let appDatabase: AppDatabase?
    let store: MCPServerConfigStore
    @State private var setupTemplate: MCPServerTemplate?

    /// Templates grouped by category for the wizard
    private var essentialTemplates: [MCPServerTemplate] {
        [.creedFlow, .filesystem, .github]
    }

    private var creativeTemplates: [MCPServerTemplate] {
        [.dalle, .figma, .stability, .elevenlabs, .runway]
    }

    private var otherTemplates: [MCPServerTemplate] {
        [.promptsChat]
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
                    ForEach(essentialTemplates) { template in
                        wizardTemplateCard(template)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Creative Tools") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(creativeTemplates) { template in
                        wizardTemplateCard(template)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Other") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(otherTemplates) { template in
                        wizardTemplateCard(template)
                    }
                }
                .padding(.vertical, 4)
            }

            if !store.configs.isEmpty {
                Section("Configured (\(store.configs.count))") {
                    ForEach(store.configs) { config in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.forgeSuccess)
                                .font(.caption)
                            Text(config.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button(role: .destructive) {
                                removeConfig(config)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.caption)
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
                            .font(.system(size: 9))
                            .foregroundStyle(.forgeSuccess)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(template.displayName)
                    .font(.caption.weight(.medium))
                Text(template.description)
                    .font(.caption2)
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
                ForEach(template.requiredInputs) { input in
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

// MARK: - Step 5: Summary

struct WizardSummaryStep: View {
    let detector: EnvironmentDetector
    let claudePathOverride: String
    let codexPathOverride: String
    let geminiPathOverride: String
    let opencodePathOverride: String
    let ollamaPathOverride: String
    let lmstudioPathOverride: String
    let llamacppPathOverride: String
    let mlxPathOverride: String
    let projectsBaseDir: String
    let maxConcurrency: Int
    let defaultBudget: Double
    let telegramConfigured: Bool
    let mcpConfigs: [MCPServerConfig]

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
                    ForEach(mcpConfigs) { config in
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
                .font(.caption)
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
                    .font(.caption)
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
                .font(.caption)
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
