import SwiftUI

struct SettingsView: View {
    @Environment(\.appDatabase) private var appDatabase
    @AppStorage("claudePath") private var claudePath = "/usr/local/bin/claude"
    @AppStorage("maxConcurrency") private var maxConcurrency = 3
    @AppStorage("telegramBotToken") private var telegramBotToken = ""
    @AppStorage("telegramChatId") private var telegramChatId = ""
    @AppStorage("defaultMaxBudgetUSD") private var defaultMaxBudgetUSD = 5.0
    @AppStorage("projectsBaseDir") private var projectsBaseDir = ""

    @State private var claudeVersion = "Checking..."
    @State private var ghVersion = "Checking..."

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            claudeTab
                .tabItem { Label("Claude", systemImage: "brain") }

            telegramTab
                .tabItem { Label("Telegram", systemImage: "paperplane") }
        }
        .frame(width: 500, height: 400)
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
                Text("Default: ~/CodeForge/projects/")
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
        }
        .formStyle(.grouped)
    }

    private var claudeTab: some View {
        Form {
            Section("Claude CLI") {
                HStack {
                    TextField("Claude CLI Path", text: $claudePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            claudePath = url.path
                        }
                    }
                }

                LabeledContent("Claude Version", value: claudeVersion)
                LabeledContent("gh CLI Version", value: ghVersion)

                Button("Verify Installation") {
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
        // Check claude
        do {
            let output = try await Process.run(claudePath, arguments: ["--version"])
            claudeVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            claudeVersion = "Not found"
        }

        // Check gh
        do {
            let output = try await Process.run("/usr/local/bin/gh", arguments: ["--version"])
            claudeVersion = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? ""
        } catch {
            ghVersion = "Not found"
        }
    }
}
