import SwiftUI
import GRDB

public struct ContentView: View {
    @Environment(\.appDatabase) private var appDatabase
    @State private var selectedSection: SidebarSection? = .projects
    @State private var selectedProjectId: UUID?
    @State private var selectedTaskId: UUID?
    @State private var orchestrator: Orchestrator?
    @State private var telegramService = TelegramBotService()
    @State private var detailHeight: CGFloat = 280

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedSection: $selectedSection,
                selectedProjectId: $selectedProjectId,
                orchestrator: orchestrator,
                appDatabase: appDatabase
            )
        } detail: {
            VSplitView {
                contentPanel
                    .frame(minHeight: 200)

                detailPanel
                    .frame(minHeight: 120, idealHeight: detailHeight)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 640)
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
                selectedTaskId: $selectedTaskId,
                appDatabase: appDatabase
            )
        case .tasks:
            if let projectId = selectedProjectId {
                TaskBoardView(
                    projectId: projectId,
                    selectedTaskId: $selectedTaskId,
                    appDatabase: appDatabase,
                    orchestrator: orchestrator
                )
            } else {
                ForgeEmptyState(
                    icon: "folder",
                    title: "Select a Project",
                    subtitle: "Choose a project from the sidebar to see its task board"
                )
            }
        case .agents:
            AgentStatusView(
                orchestrator: orchestrator,
                selectedTaskId: $selectedTaskId,
                appDatabase: appDatabase
            )
        case .costs:
            CostDashboardView(appDatabase: appDatabase)
        case .reviews:
            ReviewApprovalView(appDatabase: appDatabase)
        case .deploys:
            DeployView(appDatabase: appDatabase)
        case .settings, .none:
            ForgeEmptyState(
                icon: "hammer.fill",
                title: "CodeForge",
                subtitle: "Select a section from the sidebar to get started"
            )
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let taskId = selectedTaskId {
            TaskDetailView(
                taskId: taskId,
                appDatabase: appDatabase,
                orchestrator: orchestrator,
                onDismiss: { selectedTaskId = nil }
            )
        } else if let projectId = selectedProjectId, selectedSection == .projects {
            ProjectDetailView(
                projectId: projectId,
                appDatabase: appDatabase,
                orchestrator: orchestrator
            )
        } else {
            ForgeEmptyState(
                icon: "rectangle.bottomhalf.filled",
                title: "No Selection",
                subtitle: "Select an item to view details"
            )
        }
    }
}

enum SidebarSection: Hashable {
    case projects
    case tasks
    case agents
    case costs
    case reviews
    case deploys
    case settings
}
