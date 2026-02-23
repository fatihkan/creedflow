import SwiftUI

// MARK: - Step 1: Environment Detection

struct WizardEnvironmentStep: View {
    let detector: EnvironmentDetector
    @Binding var claudePathOverride: String

    var body: some View {
        Form {
            Section("Claude CLI") {
                DetectionRow(
                    label: "Claude CLI",
                    found: detector.claudeFound,
                    detail: detector.claudeFound
                        ? "\(detector.claudePath) (v\(detector.claudeVersion))"
                        : "Not found in common locations"
                )

                HStack {
                    TextField("Custom path", text: $claudePathOverride)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowedContentTypes = [.unixExecutable]
                        if panel.runModal() == .OK, let url = panel.url {
                            claudePathOverride = url.path
                        }
                    }
                }
                Text("Override if Claude CLI is installed at a non-standard location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Where CodeForge creates project folders. Default: ~/CodeForge/projects/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Concurrency") {
                Stepper("Max Parallel Agents: \(maxConcurrency)", value: $maxConcurrency, in: 1...8)
                Text("How many AI agents can run simultaneously")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Budget") {
                HStack {
                    Text("Default Max Budget per Task:")
                    TextField("USD", value: $defaultBudget, format: .currency(code: "USD"))
                        .frame(width: 100)
                }
                Text("Maximum Claude API cost allowed per individual task")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

// MARK: - Step 4: Summary

struct WizardSummaryStep: View {
    let detector: EnvironmentDetector
    let claudePathOverride: String
    let projectsBaseDir: String
    let maxConcurrency: Int
    let defaultBudget: Double
    let telegramConfigured: Bool

    private var effectiveClaudePath: String {
        if !claudePathOverride.isEmpty { return claudePathOverride }
        if detector.claudeFound { return detector.claudePath }
        return "Not configured"
    }

    var body: some View {
        Form {
            Section("Environment") {
                SummaryRow(label: "Claude CLI", value: effectiveClaudePath, ok: detector.claudeFound || !claudePathOverride.isEmpty)
                SummaryRow(label: "gh CLI", value: detector.ghFound ? detector.ghPath : "Not found", ok: detector.ghFound)
                SummaryRow(label: "Git user", value: detector.gitConfigured ? "\(detector.gitUserName) <\(detector.gitUserEmail)>" : "Not configured", ok: detector.gitConfigured)
            }

            Section("Projects & Budget") {
                SummaryRow(label: "Projects directory", value: projectsBaseDir.isEmpty ? "~/CodeForge/projects/" : projectsBaseDir, ok: true)
                SummaryRow(label: "Max concurrency", value: "\(maxConcurrency) agents", ok: true)
                SummaryRow(label: "Budget per task", value: String(format: "$%.2f", defaultBudget), ok: true)
            }

            Section("Integrations") {
                SummaryRow(label: "Telegram", value: telegramConfigured ? "Configured" : "Skipped", ok: telegramConfigured)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Helper Views

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
