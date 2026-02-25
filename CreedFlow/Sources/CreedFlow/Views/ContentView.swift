import SwiftUI
import GRDB

public struct ContentView: View {
    @Environment(\.appDatabase) private var appDatabase
    @State private var selectedSection: SidebarSection? = .projects
    @State private var selectedProjectId: UUID?
    @State private var selectedTaskId: UUID?
    @State private var orchestrator: Orchestrator?
    @State private var telegramService = TelegramBotService()
    @State private var keyboardMonitor: Any?

    public init() {}

    public var body: some View {
        HSplitView {
            SidebarView(
                selectedSection: $selectedSection,
                selectedProjectId: $selectedProjectId,
                orchestrator: orchestrator,
                appDatabase: appDatabase
            )
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            HStack(spacing: 0) {
                contentPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showDetailPanel {
                    Divider()
                    detailPanel
                        .frame(minWidth: 340, idealWidth: 400, maxWidth: 480)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: showDetailPanel)
        }
        .frame(minWidth: 960, minHeight: 640)
        .task {
            if let db = appDatabase {
                let orch = Orchestrator(dbQueue: db.dbQueue, telegramService: telegramService)
                orchestrator = orch
                await orch.start()

                // Start Telegram polling if configured (#32)
                let token = UserDefaults.standard.string(forKey: "telegramBotToken") ?? ""
                if !token.isEmpty {
                    let chatId = UserDefaults.standard.object(forKey: "telegramChatId") as? Int64
                    telegramService.configure(token: token, chatId: chatId)
                    telegramService.startPolling { command in
                        await handleTelegramCommand(command)
                    }
                }
            }
        }
        .onAppear {
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Escape — dismiss detail panel
                if event.keyCode == 53 {
                    if selectedTaskId != nil {
                        selectedTaskId = nil
                        return nil
                    }
                    return event
                }

                guard event.modifierFlags.contains(.command),
                      !event.modifierFlags.contains(.shift),
                      !event.modifierFlags.contains(.option) else { return event }
                switch event.charactersIgnoringModifiers {
                case "1": selectedSection = .projects; return nil
                case "2": selectedSection = .tasks; return nil
                case "3": selectedSection = .agents; return nil
                case "4": selectedSection = .reviews; return nil
                case "5": selectedSection = .deploys; return nil
                case "6": selectedSection = .prompts; return nil
                default: return event
                }
            }
        }
        .onDisappear {
            if let monitor = keyboardMonitor {
                NSEvent.removeMonitor(monitor)
                keyboardMonitor = nil
            }
            // Stop orchestrator and telegram polling on window close (#45)
            telegramService.stopPolling()
            Task {
                await orchestrator?.stop()
            }
        }
    }

    // MARK: - Detail Panel Visibility

    private var showDetailPanel: Bool {
        selectedTaskId != nil || (selectedProjectId != nil && selectedSection == .projects)
    }

    // MARK: - Content Panel

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
            TaskBoardView(
                projectId: selectedProjectId,
                selectedTaskId: $selectedTaskId,
                appDatabase: appDatabase,
                orchestrator: orchestrator
            )
        case .agents:
            AgentStatusView(
                orchestrator: orchestrator,
                selectedTaskId: $selectedTaskId,
                appDatabase: appDatabase,
                onNavigateToTasks: { selectedSection = .tasks }
            )
        case .costs:
            EmptyView() // Cost dashboard hidden for now
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
            EmptyView()
        case .none:
            ForgeEmptyState(
                icon: "hammer.fill",
                title: "CreedFlow",
                subtitle: "Select a section from the sidebar to get started"
            )
        }
    }

    // MARK: - Detail Panel

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
        }
    }
}

// MARK: - Telegram Command Handling

extension ContentView {
    func handleTelegramCommand(_ command: TelegramCommand) async {
        guard let db = appDatabase else { return }

        switch command.command {
        case "status":
            let counts = try? await db.dbQueue.read { dbConn -> (Int, Int, Int) in
                let queued = try AgentTask.filter(Column("status") == "queued").fetchCount(dbConn)
                let active = try AgentTask.filter(Column("status") == "inProgress").fetchCount(dbConn)
                let done = try AgentTask.filter(Column("status") == "passed").fetchCount(dbConn)
                return (queued, active, done)
            }
            if let (q, a, d) = counts {
                try? await telegramService.sendMessage(
                    "Queued: \(q) | Active: \(a) | Done: \(d)",
                    chatId: command.chatId
                )
            }
        case "projects":
            let projects = try? await db.dbQueue.read { dbConn in
                try Project.order(Column("name")).fetchAll(dbConn)
            }
            let list = projects?.map { "- \($0.name) (\($0.status.rawValue))" }.joined(separator: "\n") ?? "No projects"
            try? await telegramService.sendMessage(list, chatId: command.chatId)
        default:
            try? await telegramService.sendMessage(
                "Unknown command: /\(command.command)\nAvailable: /status, /projects",
                chatId: command.chatId
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
