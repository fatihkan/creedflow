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

    @State private var claudeVersion = "Checking..."
    @State private var codexVersion = "Checking..."
    @State private var geminiVersion = "Checking..."
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
        .frame(width: 550, height: 450)
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
            Section("Claude CLI") {
                CLISettingsRow(label: "Claude CLI Path", path: $claudePath, version: claudeVersion)
            }

            Section("Codex CLI") {
                CLISettingsRow(label: "Codex CLI Path", path: $codexPath, version: codexVersion)
                Text("Install: npm install -g @openai/codex")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gemini CLI") {
                CLISettingsRow(label: "Gemini CLI Path", path: $geminiPath, version: geminiVersion)
                Text("Install: npm install -g @anthropic-ai/gemini-cli")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

        // Check gh
        ghVersion = await Self.checkCLIVersion(at: "/usr/local/bin/gh")
    }

    private static func checkCLIVersion(at path: String) async -> String {
        do {
            let output = try await Process.run(path, arguments: ["--version"])
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

    var body: some View {
        HStack {
            TextField(label, text: $path)
                .textFieldStyle(.roundedBorder)
            Button("Browse") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                if panel.runModal() == .OK, let url = panel.url {
                    path = url.path
                }
            }
        }
        LabeledContent("Version", value: version)
    }
}
