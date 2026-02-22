import SwiftUI

/// Terminal-style view displaying live Claude agent output.
/// Monospace font, dark background, auto-scrolling.
struct TerminalOutputView: View {
    let runner: ClaudeAgentRunner

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(runner.liveOutput) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(line.timestamp, format: .dateTime.hour().minute().second())
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.gray)

                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(colorForType(line.type))
                                .textSelection(.enabled)
                        }
                        .id(line.id)
                    }
                }
                .padding(8)
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: runner.liveOutput.count) {
                if let last = runner.liveOutput.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func colorForType(_ type: ClaudeAgentRunner.OutputLine.LineType) -> Color {
        switch type {
        case .text: return .green
        case .toolUse: return .cyan
        case .error: return .red
        case .system: return .yellow
        }
    }
}
