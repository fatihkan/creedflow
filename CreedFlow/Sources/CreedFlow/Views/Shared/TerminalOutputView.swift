import SwiftUI
import AppKit

/// Terminal-style view displaying live agent output from any CLI backend.
/// Dark background with monospace font, auto-scrolling to latest output.
struct TerminalOutputView: View {
    let runner: MultiBackendRunner

    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar strip
            HStack(spacing: 8) {
                Text("\(runner.liveOutput.count) lines")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.forgeNeutral)

                Spacer()

                Button {
                    autoScroll.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: autoScroll ? "arrow.down.to.line" : "pause")
                            .font(.system(size: 11))
                        Text(autoScroll ? "Auto-scroll" : "Paused")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(autoScroll ? .forgeSuccess : .forgeWarning)
                }
                .buttonStyle(.plain)

                Button {
                    let text = runner.liveOutput.map { $0.text }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Copy All")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.forgeTerminalBg)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(runner.liveOutput) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(line.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.forgeNeutral)
                                    .frame(width: 60, alignment: .leading)

                                Text(line.text)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(colorForType(line.type))
                                    .textSelection(.enabled)
                            }
                            .id(line.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color.forgeTerminalBg)
                .onChange(of: runner.liveOutput.count) {
                    if autoScroll, let last = runner.liveOutput.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func colorForType(_ type: MultiBackendRunner.OutputLine.LineType) -> Color {
        switch type {
        case .text: return .forgeTerminalText
        case .toolUse: return .forgeTerminalCyan
        case .error: return .forgeTerminalRed
        case .system: return .forgeTerminalYellow
        }
    }
}
