import SwiftUI
import GRDB

struct SidebarView: View {
    @Binding var selectedSection: SidebarSection?
    @Binding var selectedProjectId: UUID?
    let orchestrator: Orchestrator?
    let appDatabase: AppDatabase?
    var notificationViewModel: NotificationViewModel?

    @State private var projects: [Project] = []
    @State private var totalProjectCount: Int = 0
    @State private var activeTaskCount: Int = 0
    @State private var archivedTaskCount: Int = 0
    @State private var pendingDeployCount: Int = 0
    @State private var isHoveringCoffee = false
    @State private var usageStore = CLIUsageStore()
    @State private var showNotificationPanel = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                Section(L("sidebar.workspace")) {
                    Label(L("sidebar.projects"), systemImage: "folder.fill")
                        .tag(SidebarSection.projects)

                    Label {
                        Text(L("sidebar.tasks"))
                    } icon: {
                        Image(systemName: "checklist")
                    }
                    .badge(activeTaskCount > 0 ? activeTaskCount : 0)
                    .tag(SidebarSection.tasks)

                    Label(L("sidebar.archive"), systemImage: "archivebox")
                        .badge(archivedTaskCount > 0 ? archivedTaskCount : 0)
                        .tag(SidebarSection.archive)
                }

                if !projects.isEmpty {
                    Section(L("sidebar.recent")) {
                        ForEach(projects.prefix(5)) { project in
                            Label {
                                Text(project.name)
                                    .lineLimit(1)
                            } icon: {
                                Circle()
                                    .fill(project.status.themeColor)
                                    .frame(width: 8, height: 8)
                            }
                            .tag(SidebarSection.projectTasks(project.id))
                        }

                        if totalProjectCount > 5 {
                            Button {
                                selectedSection = .projects
                            } label: {
                                Label("View All (\(totalProjectCount))", systemImage: "ellipsis.circle")
                                    .foregroundStyle(.forgeAmber)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section(L("sidebar.pipeline")) {
                    Label(L("sidebar.gitHistory"), systemImage: "arrow.triangle.branch")
                        .tag(SidebarSection.gitGraph)

                    Label {
                        Text(L("sidebar.deployments"))
                    } icon: {
                        Image(systemName: "arrow.up.circle")
                    }
                    .badge(pendingDeployCount > 0 ? pendingDeployCount : 0)
                    .tag(SidebarSection.deploys)
                }

                Section(L("sidebar.monitor")) {
                    Label {
                        HStack {
                            Text(L("sidebar.agents"))
                            Spacer()
                            if let orchestrator, orchestrator.isRunning {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.forgeSuccess)
                                        .frame(width: 6, height: 6)
                                    if orchestrator.activeRunners.count > 0 {
                                        Text("\(orchestrator.activeRunners.count)")
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } icon: {
                        Image(systemName: "cpu")
                    }
                    .tag(SidebarSection.agents)

                    Label(L("sidebar.compare"), systemImage: "arrow.triangle.branch")
                        .tag(SidebarSection.compareBackends)
                }

                // Usage section hidden — revisit with correct API approach
                // Section("Usage") { ... }

                Section(L("sidebar.library")) {
                    Label(L("sidebar.prompts"), systemImage: "text.book.closed")
                        .tag(SidebarSection.prompts)

                    Label(L("sidebar.assets"), systemImage: "photo.on.rectangle.angled")
                        .tag(SidebarSection.assets)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom bar
            bottomPanel
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            brandHeader
        }
        .task { await observeProjects() }
        .task { await observeActiveTaskCount() }
        .task { await observeArchivedTaskCount() }
        .task { await observePendingDeployCount() }
        // .task { await observeUsage() }
    }

    // MARK: - Brand Header

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Group {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.forgeAmber)
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("CreedFlow")
                    .font(.system(.headline, weight: .bold))
                Text("AI Orchestrator")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            orchestratorButton

            HStack {
                // Bell icon with unread badge
                if let notificationViewModel {
                    Button {
                        showNotificationPanel.toggle()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            if notificationViewModel.unreadCount > 0 {
                                Text("\(min(notificationViewModel.unreadCount, 99))")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Color.red, in: Capsule())
                                    .offset(x: 6, y: -4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Notifications\(notificationViewModel.unreadCount > 0 ? ", \(notificationViewModel.unreadCount) unread" : "")")
                    .help("Notifications")
                    .popover(isPresented: $showNotificationPanel) {
                        NotificationPanelView(viewModel: notificationViewModel)
                    }
                }

                Spacer()
            }

            HStack {
                Button {
                    if let url = URL(string: "https://github.com/fatihkan/creedflow") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                        Text("GitHub")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open GitHub Repository")

                Spacer()

                Button {
                    if let url = URL(string: "https://buymeacoffee.com/fatihkan") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("\u{2615}")
                            .font(.system(size: 12))
                        Text("Buy me a coffee")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(Color.forgeAmber.opacity(isHoveringCoffee ? 0.18 : 0.1))
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color.forgeAmber.opacity(isHoveringCoffee ? 0.3 : 0.15), lineWidth: 0.5)
                            }
                    }
                    .scaleEffect(isHoveringCoffee ? 1.03 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isHoveringCoffee)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringCoffee = $0 }
                .help("Support the project")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Orchestrator Button

    private var orchestratorButton: some View {
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
            let isRunning = orchestrator?.isRunning == true
            let accent: Color = isRunning ? .forgeSuccess : .secondary
            HStack(spacing: 8) {
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isRunning ? Color.forgeDanger : Color.forgeSuccess)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isRunning ? L("sidebar.running") : L("sidebar.startOrchestrator"))
                        .font(.system(size: 12, weight: .medium))
                    if isRunning, let orchestrator, orchestrator.activeRunners.count > 0 {
                        Text("\(orchestrator.activeRunners.count) active tasks")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isRunning {
                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                        .shadow(color: accent.opacity(0.5), radius: 3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(orchestrator?.isRunning == true ? "Stop Orchestrator" : "Start Orchestrator")
    }

    // MARK: - Data Observation

    private func observeProjects() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db -> ([Project], Int) in
            let recent = try Project.order(Column("updatedAt").desc).limit(5).fetchAll(db)
            let count = try Project.fetchCount(db)
            return (recent, count)
        }
        do {
            for try await (value, count) in observation.values(in: db.dbQueue) {
                projects = value
                totalProjectCount = count
            }
        } catch { /* observation error — sidebar badges may be stale */ }
    }

    private func observeActiveTaskCount() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try AgentTask
                .filter(Column("status") == AgentTask.Status.inProgress.rawValue)
                .fetchCount(db)
        }
        do {
            for try await count in observation.values(in: db.dbQueue) {
                activeTaskCount = count
            }
        } catch { /* observation error — sidebar badges may be stale */ }
    }

    private func observeArchivedTaskCount() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try AgentTask
                .filter(Column("archivedAt") != nil)
                .fetchCount(db)
        }
        do {
            for try await count in observation.values(in: db.dbQueue) {
                archivedTaskCount = count
            }
        } catch { /* observation error — sidebar badges may be stale */ }
    }

    private func observePendingDeployCount() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try Deployment
                .filter(Column("status") == Deployment.Status.pending.rawValue)
                .fetchCount(db)
        }
        do {
            for try await count in observation.values(in: db.dbQueue) {
                pendingDeployCount = count
            }
        } catch { /* observation error — sidebar badges may be stale */ }
    }

    private func observeUsage() async {
        guard let db = appDatabase else { return }
        usageStore.startPolling(dbQueue: db.dbQueue)
    }

    private func isBackendEnabled(_ type: CLIBackendType) -> Bool {
        UserDefaults.standard.object(forKey: "\(type.rawValue)Enabled") as? Bool ?? true
    }

    private enum UsageWindowType { case fourHour, weekly }

    private func usageLimitValue(for backend: CLIBackendType, window: UsageWindowType) -> Double {
        let suffix = window == .fourHour ? "4hLimitUSD" : "WeeklyLimitUSD"
        let key = "\(backend.rawValue)\(suffix)"
        return UserDefaults.standard.object(forKey: key) as? Double ?? (window == .fourHour ? 5.0 : 25.0)
    }
}

// MARK: - CLI Usage Row

private struct CLIUsageRow: View {
    let backend: CLIBackendType
    let usage: CLIUsageStore.BackendUsage
    let limit4h: Double
    let limitWeek: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(backend.backendColor)
                    .frame(width: 8, height: 8)
                Text(backend.displayName)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                statusIndicator
            }

            switch usage.status {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("Fetching usage...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            case .error(let message):
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            case .loaded, .idle:
                usageBar(label: "4h", cost: usage.last4h.cost, limit: limit4h)
                usageBar(label: "7d", cost: usage.lastWeek.cost, limit: limitWeek)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch usage.status {
        case .loaded:
            Text(formatCost(usage.lastWeek.cost))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        case .loading:
            ProgressView()
                .scaleEffect(0.4)
                .frame(width: 12, height: 12)
        case .idle:
            Text(formatCost(usage.lastWeek.cost))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func usageBar(label: String, cost: Double, limit: Double) -> some View {
        let fraction = limit > 0 ? min(cost / limit, 1.0) : 0
        let percent = Int(fraction * 100)
        let barColor: Color = fraction >= 0.9 ? .red : (fraction >= 0.7 ? .orange : backend.backendColor)

        return HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(0.7))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)

            Text("\(percent)%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 && cost > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", cost)
    }
}

