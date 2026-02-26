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
            // Sidebar list
            List(selection: $selectedSection) {
                workspaceSection
                projectShortcuts
                pipelineSection
                monitorSection
                promptsSection
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))

            // Bottom bar — liquid glass panel
            VStack(spacing: 6) {
                aboutButton
                subscribeButton
                orchestratorButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.06),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 0.5)
                    }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await observeProjects()
        }
        .task {
            await observeActiveTaskCount()
        }
        .task {
            await observeArchivedTaskCount()
        }
        .task {
            await observePendingDeployCount()
        }
    }

    // MARK: - Sections

    private var workspaceSection: some View {
        Section("Workspace") {
            Label("Projects", systemImage: "folder.fill")
                .tag(SidebarSection.projects)

            HStack {
                Label("Tasks", systemImage: "checklist")
                Spacer()
                if activeTaskCount > 0 {
                    Text("\(activeTaskCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.forgeInfo, in: Capsule())
                }
            }
            .tag(SidebarSection.tasks)

            HStack {
                Label("Archive", systemImage: "archivebox")
                Spacer()
                if archivedTaskCount > 0 {
                    Text("\(archivedTaskCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary, in: Capsule())
                }
            }
            .tag(SidebarSection.archive)
        }
    }

    @ViewBuilder
    private var projectShortcuts: some View {
        if !projects.isEmpty {
            Section("Recent Projects") {
                ForEach(projects.prefix(5)) { project in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(project.status.themeColor)
                            .frame(width: 6, height: 6)
                        Text(project.name)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .tag(SidebarSection.projectTasks(project.id))
                }
                if totalProjectCount > 5 {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                        Text("View All Projects")
                            .font(.footnote)
                    }
                    .foregroundStyle(.forgeAmber)
                    .tag(SidebarSection.projects)
                }
            }
        }
    }

    private var pipelineSection: some View {
        Section("Pipeline") {
            Label("Git History", systemImage: "arrow.triangle.branch")
                .tag(SidebarSection.gitGraph)

            HStack {
                Label("Deployments", systemImage: "arrow.up.circle")
                Spacer()
                if pendingDeployCount > 0 {
                    Text("\(pendingDeployCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.forgeAmber, in: Capsule())
                }
            }
            .tag(SidebarSection.deploys)
        }
    }

    private var monitorSection: some View {
        Section("Monitor") {
            HStack {
                Label("Agents", systemImage: "cpu")
                Spacer()
                agentIndicator
            }
            .tag(SidebarSection.agents)
        }
    }

    private var promptsSection: some View {
        Section("Library") {
            Label("Prompts", systemImage: "text.book.closed")
                .tag(SidebarSection.prompts)
        }
    }

    @ViewBuilder
    private var agentIndicator: some View {
        if let orchestrator, orchestrator.isRunning {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.forgeSuccess)
                    .frame(width: 6, height: 6)
                if orchestrator.activeRunners.count > 0 {
                    Text("\(orchestrator.activeRunners.count)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var aboutButton: some View {
        Button {
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Hakkında")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Hakkında")
    }

    private var subscribeButton: some View {
        Button {
            showSubscriptionSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.forgeAmber)
                Text("Abone Ol")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                Spacer()
                Text("PRO")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.forgeAmber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.forgeAmber.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.forgeAmber.opacity(0.06),
                                Color.forgeAmber.opacity(0.02)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.forgeAmber.opacity(0.15), lineWidth: 0.5)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Abone Ol")
        .sheet(isPresented: $showSubscriptionSheet) {
            SubscriptionSheetView()
        }
    }

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
            let accent: Color = isRunning ? .forgeDanger : .forgeSuccess
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(isRunning ? "Durdur" : "Başlat")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.9))
                    if isRunning, let orchestrator, orchestrator.activeRunners.count > 0 {
                        Text("\(orchestrator.activeRunners.count) aktif görev")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Orchestrator")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(accent.opacity(isRunning ? 0.2 : 0.1), lineWidth: 0.5)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(orchestrator?.isRunning == true ? "Orchestrator'ı Durdur" : "Orchestrator'ı Başlat")
        .accessibilityLabel(orchestrator?.isRunning == true ? "Durdur" : "Başlat")
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
                Text("Ufak bir destek ile siz de projeye katkı sağlayabilirsiniz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Plan cards — liquid glass
            HStack(spacing: 12) {
                planCard(
                    id: "monthly",
                    title: "Aylık",
                    price: "$9.99",
                    period: "/ay",
                    highlight: false
                )
                planCard(
                    id: "yearly",
                    title: "Yıllık",
                    price: "$99.99",
                    period: "/yıl",
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
                        Text("Stripe ile Devam Et")
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
                        Text("Giriş Yap")
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

            // Close button — top-right
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
            .help("Kapat")
        }
        .frame(width: 380, height: 440)
    }

    private func planCard(id: String, title: String, price: String, period: String, highlight: Bool) -> some View {
        let isHovered = hoveredPlan == id
        let isSelected = selectedPlan == id
        return VStack(spacing: 8) {
            HStack(spacing: 4) {
                if highlight {
                    Text("Popüler")
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
        Text("Yakında")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.6), in: Capsule())
    }
}
