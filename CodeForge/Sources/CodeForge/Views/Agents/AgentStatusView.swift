import SwiftUI

struct AgentStatusView: View {
    let orchestrator: Orchestrator?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let orchestrator {
                // Orchestrator status
                HStack {
                    Circle()
                        .fill(orchestrator.isRunning ? .green : .red)
                        .frame(width: 12, height: 12)
                    Text(orchestrator.isRunning ? "Orchestrator Running" : "Orchestrator Stopped")
                        .font(.headline)
                    Spacer()
                }
                .padding()

                // Active runners
                if orchestrator.activeRunners.isEmpty {
                    ContentUnavailableView(
                        "No Active Agents",
                        systemImage: "cpu",
                        description: Text("Agents will appear here when tasks are being processed")
                    )
                } else {
                    List {
                        ForEach(Array(orchestrator.activeRunners.keys), id: \.self) { taskId in
                            if let runner = orchestrator.activeRunners[taskId] {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("Task \(taskId.uuidString.prefix(8))")
                                            .font(.subheadline.bold())
                                        Spacer()
                                        Text("\(runner.liveOutput.count) lines")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    // Last few output lines
                                    if let lastLine = runner.liveOutput.last {
                                        Text(lastLine.text)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Orchestrator Not Initialized",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The orchestrator needs a database connection")
                )
            }
        }
        .navigationTitle("Agents")
    }
}
