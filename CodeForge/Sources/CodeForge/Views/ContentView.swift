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
    @State private var keyboardMonitor: Any?

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
                    .transition(.opacity.combined(with: .move(edge: .leading)))

                detailPanel
                    .frame(minHeight: 120, idealHeight: detailHeight)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 640)
        .task {
            if let db = appDatabase {
                let orch = Orchestrator(dbQueue: db.dbQueue, telegramService: telegramService)
                orchestrator = orch
                await orch.start()
            }
        }
        .onAppear {
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.contains(.command),
                      !event.modifierFlags.contains(.shift),
                      !event.modifierFlags.contains(.option) else { return event }
                switch event.charactersIgnoringModifiers {
                case "1": selectedSection = .projects; return nil
                case "2": selectedSection = .tasks; return nil
                case "3": selectedSection = .agents; return nil
                case "4": selectedSection = .reviews; return nil
                case "5": selectedSection = .deploys; return nil
                case "6": selectedSection = .costs; return nil
                case "7": selectedSection = .prompts; return nil
                default: return event
                }
            }
        }
        .onDisappear {
            if let monitor = keyboardMonitor {
                NSEvent.removeMonitor(monitor)
                keyboardMonitor = nil
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
                appDatabase: appDatabase,
                onViewProjectTasks: { projectId in
                    selectedSection = .projectTasks(projectId)
                }
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
                appDatabase: appDatabase,
                onNavigateToTasks: { selectedSection = .tasks }
            )
        case .costs:
            CostDashboardView(appDatabase: appDatabase)
        case .reviews:
            ReviewApprovalView(appDatabase: appDatabase)
        case .deploys:
            DeployView(appDatabase: appDatabase)
        case .prompts:
            PromptsLibraryView(appDatabase: appDatabase)
        case .projectTasks(let projectId):
            TaskBoardView(
                projectId: projectId,
                selectedTaskId: $selectedTaskId,
                appDatabase: appDatabase,
                orchestrator: orchestrator
            )
            .onAppear { selectedProjectId = projectId }
        case .settings:
            MCPSettingsView(appDatabase: appDatabase)
        case .none:
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
                orchestrator: orchestrator,
                onViewAllTasks: {
                    selectedSection = .projectTasks(projectId)
                }
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
    case prompts
    case projectTasks(UUID)
}
