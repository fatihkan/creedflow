import SwiftUI

struct SidebarView: View {
    @Binding var selectedSection: SidebarSection?
    let orchestrator: Orchestrator?

    var body: some View {
        List(selection: $selectedSection) {
            Section("Workspace") {
                Label("Projects", systemImage: "folder.fill")
                    .tag(SidebarSection.projects)

                Label("Tasks", systemImage: "checklist")
                    .tag(SidebarSection.tasks)
            }

            Section("Agents") {
                HStack {
                    Label("Agent Status", systemImage: "cpu")
                    Spacer()
                    if let orchestrator, orchestrator.isRunning {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("\(orchestrator.activeRunners.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(SidebarSection.agents)
            }

            Section("Analytics") {
                Label("Costs", systemImage: "dollarsign.circle")
                    .tag(SidebarSection.costs)
            }

            Section {
                Label("Settings", systemImage: "gear")
                    .tag(SidebarSection.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("CodeForge")
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        if let orchestrator {
                            if orchestrator.isRunning {
                                await orchestrator.stop()
                            } else {
                                await orchestrator.start()
                            }
                        }
                    }
                } label: {
                    Image(systemName: orchestrator?.isRunning == true ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundStyle(orchestrator?.isRunning == true ? .red : .green)
                }
                .help(orchestrator?.isRunning == true ? "Stop Orchestrator" : "Start Orchestrator")
            }
        }
    }
}
