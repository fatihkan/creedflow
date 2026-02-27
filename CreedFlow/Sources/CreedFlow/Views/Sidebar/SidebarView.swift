import SwiftUI
import GRDB

struct SidebarView: View {
    @Binding var selectedSection: SidebarSection?
    @Binding var selectedProjectId: UUID?
    let orchestrator: Orchestrator?
    let appDatabase: AppDatabase?

    @State private var projects: [Project] = []
    @State private var totalProjectCount: Int = 0
    @State private var activeTaskCount: Int = 0
    @State private var archivedTaskCount: Int = 0
    @State private var pendingDeployCount: Int = 0
    @State private var showSubscriptionSheet = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                Section("Workspace") {
                    Label("Projects", systemImage: "folder.fill")
                        .tag(SidebarSection.projects)

                    Label {
                        Text("Tasks")
                    } icon: {
                        Image(systemName: "checklist")
                    }
                    .badge(activeTaskCount > 0 ? activeTaskCount : 0)
                    .tag(SidebarSection.tasks)

                    Label("Archive", systemImage: "archivebox")
                        .badge(archivedTaskCount > 0 ? archivedTaskCount : 0)
                        .tag(SidebarSection.archive)
                }

                if !projects.isEmpty {
                    Section("Recent") {
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

                Section("Pipeline") {
                    Label("Git History", systemImage: "arrow.triangle.branch")
                        .tag(SidebarSection.gitGraph)

                    Label {
                        Text("Deployments")
                    } icon: {
                        Image(systemName: "arrow.up.circle")
                    }
                    .badge(pendingDeployCount > 0 ? pendingDeployCount : 0)
                    .tag(SidebarSection.deploys)
                }

                Section("Monitor") {
                    Label {
                        HStack {
                            Text("Agents")
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
                }

                Section("Library") {
                    Label("Prompts", systemImage: "text.book.closed")
                        .tag(SidebarSection.prompts)
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
                    showSubscriptionSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.forgeAmber)
                        Text("PRO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.forgeAmber)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.forgeAmber.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Subscribe to Pro")
                .sheet(isPresented: $showSubscriptionSheet) {
                    SubscriptionSheetView()
                }
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
                    Text(isRunning ? "Running" : "Start Orchestrator")
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
}

// MARK: - Subscription Sheet

struct SubscriptionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hoveredPlan: String?
    @State private var selectedPlan: String?

    private static let monthlyCheckoutURL = URL(string: "https://buy.stripe.com/test_monthly")!
    private static let yearlyCheckoutURL = URL(string: "https://buy.stripe.com/test_yearly")!

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
            // Header with app icon
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.forgeAmber.opacity(0.15), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)
                    if let appIcon = NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    }
                }
                Text("CreedFlow Pro")
                    .font(.system(.title2, weight: .bold))
                Text("Support the project and unlock all features")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Plan cards
            HStack(spacing: 12) {
                planCard(
                    id: "monthly",
                    title: "Monthly",
                    price: "$9.99",
                    period: "/mo",
                    highlight: false
                )
                planCard(
                    id: "yearly",
                    title: "Yearly",
                    price: "$99.99",
                    period: "/yr",
                    highlight: true
                )
            }
            .padding(.horizontal, 24)

            // Action buttons
            VStack(spacing: 10) {
                Button {
                    if let url = selectedCheckoutURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                        Text("Continue with Stripe")
                            .font(.system(.body, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.forgeAmber)
                .disabled(selectedPlan == nil)

                Button {} label: {
                    HStack(spacing: 8) {
                        Text("Sign In")
                            .font(.system(.body, weight: .medium))
                        comingSoonBadge
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .help("Close")
        }
        .frame(width: 380, height: 440)
    }

    private func planCard(id: String, title: String, price: String, period: String, highlight: Bool) -> some View {
        let isHovered = hoveredPlan == id
        let isSelected = selectedPlan == id
        return VStack(spacing: 8) {
            HStack(spacing: 4) {
                if highlight {
                    Text("Popular")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.forgeAmber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.forgeAmber.opacity(0.12), in: Capsule())
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.forgeAmber)
                }
            }
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(price)
                    .font(.system(.title2, weight: .bold))
                Text(period)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(highlight || isSelected ? 0.08 : 0.04),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .shadow(
                    color: isSelected ? Color.forgeAmber.opacity(0.18) : (highlight ? Color.forgeAmber.opacity(0.12) : Color.black.opacity(0.06)),
                    radius: isHovered || isSelected ? 8 : 4,
                    y: 2
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.forgeAmber.opacity(0.7)
                        : (highlight
                            ? Color.forgeAmber.opacity(isHovered ? 0.5 : 0.3)
                            : Color.primary.opacity(isHovered ? 0.12 : 0.06)),
                    lineWidth: isSelected ? 1.5 : (highlight ? 1 : 0.5)
                )
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .onHover { hovering in
            hoveredPlan = hovering ? id : nil
        }
        .onTapGesture {
            selectedPlan = id
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var selectedCheckoutURL: URL? {
        switch selectedPlan {
        case "monthly": return Self.monthlyCheckoutURL
        case "yearly": return Self.yearlyCheckoutURL
        default: return nil
        }
    }

    private var comingSoonBadge: some View {
        Text("Coming Soon")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.6), in: Capsule())
    }
}
