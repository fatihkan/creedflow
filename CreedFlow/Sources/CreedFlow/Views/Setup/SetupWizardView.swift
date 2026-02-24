import SwiftUI

public struct SetupWizardView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @AppStorage("claudePath") private var storedClaudePath = ""
    @AppStorage("codexPath") private var storedCodexPath = ""
    @AppStorage("geminiPath") private var storedGeminiPath = ""
    @AppStorage("projectsBaseDir") private var storedProjectsBaseDir = ""
    @AppStorage("maxConcurrency") private var storedMaxConcurrency = 3
    @AppStorage("defaultMaxBudgetUSD") private var storedDefaultBudget = 5.0
    @AppStorage("telegramBotToken") private var storedTelegramToken = ""
    @AppStorage("telegramChatId") private var storedTelegramChatId = ""

    @State private var currentStep = 0
    @State private var detector = EnvironmentDetector()

    // Local wizard state (written to AppStorage on completion)
    @State private var claudePathOverride = ""
    @State private var codexPathOverride = ""
    @State private var geminiPathOverride = ""
    @State private var projectsBaseDir = ""
    @State private var maxConcurrency = 3
    @State private var defaultBudget = 5.0
    @State private var telegramBotToken = ""
    @State private var telegramChatId = ""

    private let totalSteps = 4
    private let stepTitles = ["Environment", "Projects & Budget", "Integrations", "Summary"]

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
                    .font(.caption)
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
                        claudePathOverride: $claudePathOverride,
                        codexPathOverride: $codexPathOverride,
                        geminiPathOverride: $geminiPathOverride
                    )
                case 1:
                    WizardProjectsStep(
                        projectsBaseDir: $projectsBaseDir,
                        maxConcurrency: $maxConcurrency,
                        defaultBudget: $defaultBudget
                    )
                case 2:
                    WizardIntegrationsStep(
                        telegramBotToken: $telegramBotToken,
                        telegramChatId: $telegramChatId
                    )
                case 3:
                    WizardSummaryStep(
                        detector: detector,
                        claudePathOverride: claudePathOverride,
                        codexPathOverride: codexPathOverride,
                        geminiPathOverride: geminiPathOverride,
                        projectsBaseDir: projectsBaseDir,
                        maxConcurrency: maxConcurrency,
                        defaultBudget: defaultBudget,
                        telegramConfigured: !telegramBotToken.isEmpty
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

                if currentStep == 2 {
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
        .frame(width: 600, height: 580)
        .task {
            await detector.detectAll()
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
