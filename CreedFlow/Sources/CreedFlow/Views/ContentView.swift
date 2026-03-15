import SwiftUI
import GRDB

public struct ContentView: View {
    @Environment(\.appDatabase) private var appDatabase
    @State private var selectedSection: SidebarSection? = .projects
    @State private var selectedProjectId: UUID?
    @State private var selectedTaskId: UUID?
    @State private var selectedDeploymentId: UUID?
    @State private var showChatPanel = false
    @State private var chatProjectId: UUID?
    @State private var orchestrator: Orchestrator?
    @State private var chatServices: [UUID: ProjectChatService] = [:]
    @State private var telegramService = TelegramBotService()
    @State private var slackService = SlackNotificationService()
    @State private var localWebServer: LocalWebServer?
    @State private var keyboardMonitor: Any?
    @State private var notificationViewModel: NotificationViewModel?
    @State private var showShortcutsOverlay = false
    @State private var updateInfo: UpdateInfo?
    @AppStorage("fontSizePreference") private var fontSizePreference = "normal"
    @AppStorage("webhookServerEnabled") private var webhookEnabled = false
    @AppStorage("webhookPort") private var webhookPort = "8080"
    @AppStorage("webhookApiKey") private var webhookApiKey = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
        // Update banner
        if let info = updateInfo {
            UpdateBannerView(updateInfo: info) {
                // Dismiss and remember version
                UserDefaults.standard.set(info.latestVersion, forKey: "dismissedUpdateVersion")
                withAnimation(.easeInOut(duration: 0.15)) { updateInfo = nil }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        ZStack {
        HSplitView {
            SidebarView(
                selectedSection: $selectedSection,
                selectedProjectId: $selectedProjectId,
                orchestrator: orchestrator,
                appDatabase: appDatabase,
                notificationViewModel: notificationViewModel
            )
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            HStack(spacing: 0) {
                // Left: Chat panel (slide-in from left)
                if showChatPanel, let chatProjId = chatProjectId {
                    ProjectChatView(
                        projectId: chatProjId,
                        appDatabase: appDatabase,
                        orchestrator: orchestrator,
                        chatService: chatServiceFor(chatProjId),
                        onDismiss: { showChatPanel = false }
                    )
                    .frame(minWidth: 340, idealWidth: 400, maxWidth: 440)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }

                // Center: Content
                contentPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right: Detail panel
                if showDetailPanel {
                    Divider()
                    detailPanel
                        .frame(minWidth: 340, idealWidth: 400, maxWidth: 480)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: showDetailPanel)
            .animation(.easeInOut(duration: 0.2), value: showChatPanel)
        }
        // Toast overlay
        if let notificationViewModel {
            NotificationToastOverlay(viewModel: notificationViewModel)
                .allowsHitTesting(true)
        }
        // Keyboard shortcuts overlay
        if showShortcutsOverlay {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showShortcutsOverlay = false }
            KeyboardShortcutsView(isPresented: $showShortcutsOverlay)
        }
        } // end ZStack
        } // end VStack
        .dynamicTypeSize(DynamicTypeSize.from(preference: fontSizePreference))
        .frame(minWidth: 960, minHeight: 640)
        .onChange(of: selectedSection) { _, newSection in
            if newSection != .deploys {
                selectedDeploymentId = nil
            }
            // Close chat panel when navigating away from project tasks
            switch newSection {
            case .projectTasks:
                break
            default:
                showChatPanel = false
            }
        }
        .task {
            if let db = appDatabase {
                let orch = Orchestrator(dbQueue: db.dbQueue, telegramService: telegramService, slackService: slackService)
                orchestrator = orch

                // Set up notification view model
                let nvm = NotificationViewModel(dbQueue: db.dbQueue, service: orch.notificationService)
                notificationViewModel = nvm
                nvm.startObserving()

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

                // Configure Slack if webhook URL is set (#228)
                let slackUrl = UserDefaults.standard.string(forKey: "slackWebhookUrl") ?? ""
                if !slackUrl.isEmpty {
                    slackService.configure(webhookUrl: slackUrl)
                }

                // Start local web dashboard if webhook server is enabled (#234)
                if webhookEnabled {
                    let port = UInt16(webhookPort) ?? 8080
                    let key = webhookApiKey.isEmpty ? nil : webhookApiKey
                    let server = LocalWebServer(port: port, apiKey: key, dbQueue: db.dbQueue)
                    localWebServer = server
                    await server.start()
                }
            }
        }
        .task {
            let checker = UpdateChecker()
            if let info = await checker.checkForUpdates() {
                let dismissed = UserDefaults.standard.string(forKey: "dismissedUpdateVersion")
                if dismissed != info.latestVersion {
                    withAnimation(.easeInOut(duration: 0.3)) { updateInfo = info }
                }
            }
        }
        .onAppear {
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Escape — dismiss panels
                if event.keyCode == 53 {
                    if showShortcutsOverlay {
                        showShortcutsOverlay = false
                        return nil
                    }
                    if selectedTaskId != nil {
                        selectedTaskId = nil
                        return nil
                    }
                    if selectedDeploymentId != nil {
                        selectedDeploymentId = nil
                        return nil
                    }
                    if showChatPanel {
                        showChatPanel = false
                        return nil
                    }
                    return event
                }

                // Cmd+? (Cmd+Shift+/) — keyboard shortcuts overlay
                if event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift),
                   event.charactersIgnoringModifiers == "/" {
                    showShortcutsOverlay.toggle()
                    return nil
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
                case "7": selectedSection = .assets; return nil
                case "8": selectedSection = .gitGraph; return nil
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
            notificationViewModel?.stopObserving()
            Task {
                await orchestrator?.stop()
                await localWebServer?.stop()
            }
        }
    }

    // MARK: - Chat Service Cache

    private func chatServiceFor(_ projectId: UUID) -> ProjectChatService {
        if let existing = chatServices[projectId] {
            return existing
        }
        guard let db = appDatabase, let orchestrator else {
            // Fallback — should not happen in practice since orchestrator is set in .task
            guard let fallbackDb = try? DatabaseQueue() else {
                fatalError("Failed to create fallback DatabaseQueue for chat service")
            }
            let fallback = ProjectChatService(
                dbQueue: fallbackDb,
                backendRouter: BackendRouter()
            )
            return fallback
        }
        let service = ProjectChatService(
            dbQueue: db.dbQueue,
            backendRouter: orchestrator.backendRouter
        )
        service.bind(to: projectId)
        chatServices[projectId] = service
        return service
    }

    // MARK: - Detail Panel Visibility

    private var showDetailPanel: Bool {
        selectedTaskId != nil
            || (selectedProjectId != nil && selectedSection == .projects)
            || (selectedDeploymentId != nil && selectedSection == .deploys)
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
                projectId: nil,
                selectedTaskId: $selectedTaskId,
                appDatabase: appDatabase,
                orchestrator: orchestrator,
                onNavigateToSettings: { selectedSection = .settings },
                showChatPanel: $showChatPanel,
                onChatProjectChanged: { chatProjectId = $0 }
            )
        case .archive:
            ArchivedTasksView(appDatabase: appDatabase, selectedTaskId: $selectedTaskId)
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
            DeployView(appDatabase: appDatabase, selectedDeploymentId: $selectedDeploymentId)
        case .prompts:
            PromptsLibraryView(appDatabase: appDatabase)
        case .assets:
            ProjectAssetsView(appDatabase: appDatabase, selectedProjectId: $selectedProjectId)
        case .gitGraph:
            GitGraphView(appDatabase: appDatabase)
        case .compareBackends:
            CompareBackendsView(orchestrator: orchestrator)
        case .automation:
            AutomationFlowsView(appDatabase: appDatabase)
        case .projectTasks(let projectId):
            TaskBoardView(
                projectId: projectId,
                selectedTaskId: $selectedTaskId,
                appDatabase: appDatabase,
                orchestrator: orchestrator,
                onNavigateToSettings: { selectedSection = .settings },
                showChatPanel: $showChatPanel,
                onChatProjectChanged: { chatProjectId = $0 }
            )
            .onAppear {
                selectedProjectId = projectId
                chatProjectId = projectId
                showChatPanel = true
            }
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
        } else if let deploymentId = selectedDeploymentId, selectedSection == .deploys {
            DeploymentDetailView(
                deploymentId: deploymentId,
                appDatabase: appDatabase,
                onDismiss: { selectedDeploymentId = nil }
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
    case archive
    case agents
    case costs
    case reviews
    case deploys
    case settings
    case prompts
    case assets
    case gitGraph
    case compareBackends
    case automation
    case projectTasks(UUID)
}
