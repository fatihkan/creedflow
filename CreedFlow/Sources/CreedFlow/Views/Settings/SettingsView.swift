import SwiftUI

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

    @State private var claudeVersion = "Checking..."
    @State private var codexVersion = "Checking..."
    @State private var geminiVersion = "Checking..."
    @State private var ollamaVersion = "Checking..."
    @State private var lmstudioVersion = "Checking..."
    @State private var llamacppVersion = "Checking..."
    @State private var mlxVersion = "Checking..."
    @State private var ghVersion = "Checking..."

    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            aiCLIsTab
                .tabItem { Label("AI CLIs", systemImage: "brain") }

            telegramTab
                .tabItem { Label("Telegram", systemImage: "paperplane") }

            MCPSettingsView(appDatabase: appDatabase)
                .tabItem { Label("MCP", systemImage: "server.rack") }
        }
        .frame(width: 550, height: 600)
        .task {
            await checkToolVersions()
        }
    }

    private var generalTab: some View {
        Form {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Budget") {
                HStack {
                    Text("Default Max Budget per Task:")
                    TextField("USD", value: $defaultMaxBudgetUSD, format: .currency(code: "USD"))
                        .frame(width: 100)
                }
            }

            Section("Setup") {
                Button("Re-run Setup Wizard") {
                    hasCompletedSetup = false
                }
                Text("Reset and walk through the initial setup wizard again")
                    .font(.caption)
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
            } header: {
                HStack {
                    Text("Claude CLI")
                    if claudeEnabled {
                        Text("Active").font(.caption2).foregroundStyle(.green)
                    } else {
                        Text("Disabled").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Enabled", isOn: $codexEnabled)
                CLISettingsRow(label: "Codex CLI Path", path: $codexPath, version: codexVersion, enabled: codexEnabled)
                Text("Install: npm install -g @openai/codex")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("Codex CLI")
                    if codexEnabled {
                        Text("Active").font(.caption2).foregroundStyle(.green)
                    } else {
                        Text("Disabled").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Enabled", isOn: $geminiEnabled)
                CLISettingsRow(label: "Gemini CLI Path", path: $geminiPath, version: geminiVersion, enabled: geminiEnabled)
                Text("Install: npm install -g @anthropic-ai/gemini-cli")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("Gemini CLI")
                    if geminiEnabled {
                        Text("Active").font(.caption2).foregroundStyle(.green)
                    } else {
                        Text("Disabled").font(.caption2).foregroundStyle(.secondary)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("Ollama")
                    if ollamaEnabled {
                        Text("Active").font(.caption2).foregroundStyle(.green)
                    } else {
                        Text("Disabled").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Enabled", isOn: $lmstudioEnabled)
                TextField("Model (e.g. default)", text: $lmstudioModel)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!lmstudioEnabled)
                Text("Install LM Studio from lmstudio.ai — runs on localhost:1234")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("LM Studio")
                    if lmstudioEnabled {
                        Text("Active").font(.caption2).foregroundStyle(.green)
                    } else {
                        Text("Disabled").font(.caption2).foregroundStyle(.secondary)
                    }
                }
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("llama.cpp")
                    if llamacppEnabled {
                        Text("Active").font(.caption2).foregroundStyle(.green)
                    } else {
                        Text("Disabled").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Enabled", isOn: $mlxEnabled)
                CLISettingsRow(label: "mlx_lm.generate Path", path: $mlxPath, version: mlxVersion, enabled: mlxEnabled)
                TextField("Model (e.g. mlx-community/Llama-3.2-3B-Instruct-4bit)", text: $mlxModel)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!mlxEnabled)
                Text("Install: pip install mlx-lm — Apple Silicon only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("MLX-LM")
                    if mlxEnabled {
                        Text("Active").font(.caption2).foregroundStyle(.green)
                    } else {
                        Text("Disabled").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

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

    private var telegramTab: some View {
        Form {
            Section("Telegram Bot") {
                SecureField("Bot Token", text: $telegramBotToken)
                    .textFieldStyle(.roundedBorder)
                TextField("Default Chat ID", text: $telegramChatId)
                    .textFieldStyle(.roundedBorder)
                Text("Get a bot token from @BotFather on Telegram")
                    .font(.caption)
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
