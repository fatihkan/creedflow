import SwiftUI

/// Terminal-style view displaying live Claude agent output.
/// Dark background with monospace font, auto-scrolling to latest output.
struct TerminalOutputView: View {
    let runner: ClaudeAgentRunner

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(runner.liveOutput) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.timestamp, format: .dateTime.hour().minute().second())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.forgeNeutral)
                                .frame(width: 60, alignment: .leading)

                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(colorForType(line.type))
                                .textSelection(.enabled)
                        }
                        .id(line.id)
                    }
                }
                .padding(8)
            }
            .background(Color.forgeTerminalBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: runner.liveOutput.count) {
                if let last = runner.liveOutput.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func colorForType(_ type: ClaudeAgentRunner.OutputLine.LineType) -> Color {
        switch type {
        case .text: return .forgeTerminalText
        case .toolUse: return .forgeTerminalCyan
        case .error: return .forgeTerminalRed
        case .system: return .forgeTerminalYellow
        }
    }
}
