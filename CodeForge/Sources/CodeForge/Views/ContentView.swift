import SwiftUI
import GRDB

public struct ContentView: View {
    @Environment(\.appDatabase) private var appDatabase
    @State private var selectedSection: SidebarSection? = .projects
    @State private var selectedProjectId: UUID?
    @State private var selectedTaskId: UUID?
    @State private var orchestrator: Orchestrator?
    @State private var telegramService = TelegramBotService()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedSection: $selectedSection,
                orchestrator: orchestrator
            )
        } detail: {
            VSplitView {
                contentPanel
                    .frame(minHeight: 200)

                detailPanel
                    .frame(minHeight: 150, idealHeight: 250)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .task {
            if let db = appDatabase {
                let orch = Orchestrator(dbQueue: db.dbQueue)
                orchestrator = orch
                await orch.start()
            }
        }
    }

    @ViewBuilder
    private var contentPanel: some View {
        switch selectedSection {
        case .projects:
            ProjectListView(
                selectedProjectId: $selectedProjectId,
                appDatabase: appDatabase
            )
        case .tasks:
            if let projectId = selectedProjectId {
                TaskBoardView(
                    projectId: projectId,
                    selectedTaskId: $selectedTaskId,
                    appDatabase: appDatabase
                )
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "folder",
                    description: Text("Choose a project to see its tasks")
                )
            }
        case .agents:
            AgentStatusView(orchestrator: orchestrator)
        case .costs:
            CostDashboardView(appDatabase: appDatabase)
        case .settings, .none:
            ContentUnavailableView(
                "CodeForge",
                systemImage: "hammer.fill",
                description: Text("Select a section from the sidebar")
            )
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let taskId = selectedTaskId {
            TaskDetailView(
                taskId: taskId,
                appDatabase: appDatabase,
                orchestrator: orchestrator
            )
        } else if let projectId = selectedProjectId, selectedSection == .projects {
            ProjectDetailView(
                projectId: projectId,
                appDatabase: appDatabase,
                orchestrator: orchestrator
            )
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "rectangle.bottomhalf.filled",
                description: Text("Select an item to view details")
            )
        }
    }
}

enum SidebarSection: Hashable {
    case projects
    case tasks
    case agents
    case costs
    case settings
}
