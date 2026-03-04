import SwiftUI

struct CompareBackendsView: View {
    let orchestrator: Orchestrator?

    @State private var prompt = ""
    @State private var selectedBackends: Set<CLIBackendType> = [.claude, .codex, .gemini]
    @State private var runner: BackendComparisonRunner?
    @State private var hasRun = false

    private let availableBackends: [CLIBackendType] = CLIBackendType.allCases

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Compare Backends") {}

            Divider()

            // Input area
            VStack(alignment: .leading, spacing: 10) {
                Text("Prompt")
                    .font(.headline)
                TextEditor(text: $prompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 120)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary, lineWidth: 0.5))

                HStack(spacing: 12) {
                    Text("Backends")
                        .font(.subheadline.bold())

                    ForEach(availableBackends, id: \.self) { type in
                        Toggle(isOn: Binding(
                            get: { selectedBackends.contains(type) },
                            set: { isOn in
                                if isOn { selectedBackends.insert(type) }
                                else { selectedBackends.remove(type) }
                            }
                        )) {
                            Text(type.displayName)
                                .font(.caption)
                        }
                        .toggleStyle(.checkbox)
                    }

                    Spacer()

                    Button {
                        Task { await runComparison() }
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedBackends.isEmpty || (runner?.isRunning ?? false))
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()

            Divider()

            // Results area
            if let runner {
                if runner.isRunning {
                    VStack {
                        ProgressView("Running comparison…")
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hasRun {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(runner.results) { result in
                                resultCard(result)
                            }
                        }
                        .padding()
                    }
                } else {
                    ForgeEmptyState(
                        icon: "arrow.triangle.branch",
                        title: "Compare AI Backends",
                        subtitle: "Enter a prompt and select backends to compare outputs side by side"
                    )
                }
            } else {
                ForgeEmptyState(
                    icon: "arrow.triangle.branch",
                    title: "Compare AI Backends",
                    subtitle: "Enter a prompt and select backends to compare outputs side by side"
                )
            }
        }
    }

    @ViewBuilder
    private func resultCard(_ result: BackendComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.backendType.displayName)
                    .forgeBadge(color: .forgeInfo)
                Spacer()
                Text("\(result.durationMs)ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = result.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.red.opacity(0.08)))
            } else {
                ScrollView {
                    Text(result.output)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.2)))
            }
        }
        .padding()
        .frame(idealWidth: 340, maxHeight: .infinity)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 0.5))
    }

    private func runComparison() async {
        guard let orchestrator else { return }
        let r = BackendComparisonRunner(backendRouter: orchestrator.backendRouter)
        runner = r
        hasRun = true
        await r.compare(prompt: prompt, backends: Array(selectedBackends))
    }
}
