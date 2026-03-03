import SwiftUI
import GRDB

public struct SetupWizardView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @AppStorage("claudePath") private var storedClaudePath = ""
    @AppStorage("codexPath") private var storedCodexPath = ""
    @AppStorage("geminiPath") private var storedGeminiPath = ""
    @AppStorage("opencodePath") private var storedOpencodePath = ""
    @AppStorage("openclawPath") private var storedOpenclawPath = ""
    @AppStorage("qwenPath") private var storedQwenPath = ""
    @AppStorage("ollamaPath") private var storedOllamaPath = ""
    @AppStorage("lmstudioEnabled") private var storedLmstudioEnabled = false
    @AppStorage("llamacppPath") private var storedLlamacppPath = ""
    @AppStorage("mlxPath") private var storedMlxPath = ""
    @AppStorage("projectsBaseDir") private var storedProjectsBaseDir = ""
    @AppStorage("maxConcurrency") private var storedMaxConcurrency = 3
    @AppStorage("defaultMaxBudgetUSD") private var storedDefaultBudget = 5.0
    @AppStorage("telegramBotToken") private var storedTelegramToken = ""
    @AppStorage("telegramChatId") private var storedTelegramChatId = ""
    @AppStorage("preferredEditor") private var storedPreferredEditor = ""

    @Environment(\.appDatabase) private var appDatabase

    @State private var currentStep = 0
    @State private var detector = EnvironmentDetector()
    @State private var installer = DependencyInstaller()
    @State private var mcpStore = MCPServerConfigStore()

    // Local wizard state (written to AppStorage on completion)
    @State private var claudePathOverride = ""
    @State private var codexPathOverride = ""
    @State private var geminiPathOverride = ""
    @State private var opencodePathOverride = ""
    @State private var openclawPathOverride = ""
    @State private var qwenPathOverride = ""
    @State private var ollamaPathOverride = ""
    @State private var lmstudioPathOverride = ""
    @State private var llamacppPathOverride = ""
    @State private var mlxPathOverride = ""
    @State private var projectsBaseDir = ""
    @State private var maxConcurrency = 3
    @State private var defaultBudget = 5.0
    @State private var telegramBotToken = ""
    @State private var telegramChatId = ""
    @State private var selectedEditor = ""
    @State private var gitUserNameInput = ""
    @State private var gitUserEmailInput = ""

    private let totalSteps = 6
    private let stepTitles = ["Environment", "Dependencies", "Projects & Budget", "Integrations", "MCP Servers", "Summary"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.forgeAmber)
                Text("Welcome to CreedFlow")
                    .font(.title2.bold())
                Text("Let's set up your environment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Progress bar
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(step <= currentStep ? Color.forgeAmber : Color.forgeNeutral.opacity(0.3))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 32)

                Text("Step \(currentStep + 1) of \(totalSteps): \(stepTitles[currentStep])")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            Divider()

            // Step content
            Group {
                switch currentStep {
                case 0:
                    WizardEnvironmentStep(
                        detector: detector,
                        installer: installer,
                        claudePathOverride: $claudePathOverride,
                        codexPathOverride: $codexPathOverride,
                        geminiPathOverride: $geminiPathOverride,
                        opencodePathOverride: $opencodePathOverride,
                        openclawPathOverride: $openclawPathOverride,
                        qwenPathOverride: $qwenPathOverride,
                        ollamaPathOverride: $ollamaPathOverride,
                        lmstudioPathOverride: $lmstudioPathOverride,
                        llamacppPathOverride: $llamacppPathOverride,
                        mlxPathOverride: $mlxPathOverride,
                        selectedEditor: $selectedEditor,
                        gitUserNameInput: $gitUserNameInput,
                        gitUserEmailInput: $gitUserEmailInput
                    )
                case 1:
                    WizardDependenciesStep(installer: installer)
                case 2:
                    WizardProjectsStep(
                        projectsBaseDir: $projectsBaseDir,
                        maxConcurrency: $maxConcurrency,
                        defaultBudget: $defaultBudget
                    )
                case 3:
                    WizardIntegrationsStep(
                        telegramBotToken: $telegramBotToken,
                        telegramChatId: $telegramChatId
                    )
                case 4:
                    WizardMCPStep(
                        appDatabase: appDatabase,
                        store: mcpStore
                    )
                case 5:
                    WizardSummaryStep(
                        detector: detector,
                        claudePathOverride: claudePathOverride,
                        codexPathOverride: codexPathOverride,
                        geminiPathOverride: geminiPathOverride,
                        opencodePathOverride: opencodePathOverride,
                        openclawPathOverride: openclawPathOverride,
                        qwenPathOverride: qwenPathOverride,
                        ollamaPathOverride: ollamaPathOverride,
                        lmstudioPathOverride: lmstudioPathOverride,
                        llamacppPathOverride: llamacppPathOverride,
                        mlxPathOverride: mlxPathOverride,
                        projectsBaseDir: projectsBaseDir,
                        maxConcurrency: maxConcurrency,
                        defaultBudget: defaultBudget,
                        telegramConfigured: !telegramBotToken.isEmpty,
                        mcpConfigs: mcpStore.configs,
                        selectedEditor: selectedEditor
                    )
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }

                Spacer()

                if currentStep == 1 || currentStep == 3 || currentStep == 4 {
                    Button("Skip") {
                        withAnimation { currentStep += 1 }
                    }
                    .foregroundStyle(.secondary)
                }

                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.forgeAmber)
                } else {
                    Button("Get Started") {
                        applySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.forgeSuccess)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 640, height: 620)
        .task {
            await detector.detectAll()
            await installer.detectAll()
        }
        .onAppear {
            if let db = appDatabase {
                mcpStore.observe(in: db.dbQueue)
            }
        }
    }

    private func applySettings() {
        // Write AI CLI paths
        if !claudePathOverride.isEmpty {
            storedClaudePath = claudePathOverride
        } else if detector.claudeFound {
            storedClaudePath = detector.claudePath
        }

        if !codexPathOverride.isEmpty {
            storedCodexPath = codexPathOverride
        } else if detector.codexFound {
            storedCodexPath = detector.codexPath
        }

        if !geminiPathOverride.isEmpty {
            storedGeminiPath = geminiPathOverride
        } else if detector.geminiFound {
            storedGeminiPath = detector.geminiPath
        }

        if !opencodePathOverride.isEmpty {
            storedOpencodePath = opencodePathOverride
        } else if detector.opencodeFound {
            storedOpencodePath = detector.opencodePath
        }

        if !openclawPathOverride.isEmpty {
            storedOpenclawPath = openclawPathOverride
        } else if detector.openclawFound {
            storedOpenclawPath = detector.openclawPath
        }

        if !qwenPathOverride.isEmpty {
            storedQwenPath = qwenPathOverride
        } else if detector.qwenFound {
            storedQwenPath = detector.qwenPath
        }

        if !ollamaPathOverride.isEmpty {
            storedOllamaPath = ollamaPathOverride
        } else if detector.ollamaFound {
            storedOllamaPath = detector.ollamaPath
        }

        if !llamacppPathOverride.isEmpty {
            storedLlamacppPath = llamacppPathOverride
        } else if detector.llamacppFound {
            storedLlamacppPath = detector.llamacppPath
        }

        if !mlxPathOverride.isEmpty {
            storedMlxPath = mlxPathOverride
        } else if detector.mlxFound {
            storedMlxPath = detector.mlxPath
        }

        // Write preferred editor
        storedPreferredEditor = selectedEditor

        // Write projects settings
        storedProjectsBaseDir = projectsBaseDir
        storedMaxConcurrency = maxConcurrency
        storedDefaultBudget = defaultBudget

        // Write telegram settings
        storedTelegramToken = telegramBotToken
        storedTelegramChatId = telegramChatId

        // Create projects directory if specified
        let dirPath = projectsBaseDir.isEmpty
            ? "\(FileManager.default.homeDirectoryForCurrentUser.path)/CreedFlow/projects"
            : projectsBaseDir
        try? FileManager.default.createDirectory(
            atPath: dirPath,
            withIntermediateDirectories: true
        )

        // Mark setup complete
        hasCompletedSetup = true
    }
}
