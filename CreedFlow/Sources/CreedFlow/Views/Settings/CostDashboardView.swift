import SwiftUI
import GRDB
import AppKit

struct CostDashboardView: View {
    let appDatabase: AppDatabase?

    @State private var costEntries: [CostTracking] = []
    @State private var totalCost: Double = 0
    @State private var costByAgent: [AgentTask.AgentType: Double] = [:]
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var visibleCount: Int = 20
    @State private var selectedTab: DashboardTab = .costs
    // Task statistics
    @State private var tasksByAgent: [(agentType: AgentTask.AgentType, total: Int, passed: Int, failed: Int, needsRevision: Int, avgDurationMs: Double?)] = []
    @State private var dailyCompleted: [(date: String, count: Int)] = []
    @State private var totalTasks: Int = 0
    @State private var successRate: Double = 0
    @State private var avgDurationMs: Double? = nil
    // Backend scores & budgets
    @State private var backendScores: [BackendScore] = []
    @State private var costBudgets: [CostBudget] = []
    @State private var budgetAlerts: [BudgetAlert] = []
    @State private var budgetSpending: [UUID: Double] = [:]
    // Budget form
    @State private var showBudgetForm = false
    @State private var editingBudget: CostBudget?

    private enum DashboardTab: String, CaseIterable {
        case costs = "Costs"
        case tasks = "Tasks"
        case performance = "Performance"
        case efficiency = "Efficiency"
        case budgets = "Budgets"
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Dashboard") {
                if selectedTab == .costs {
                    Button {
                        exportCSV()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(costEntries.isEmpty)
                    .help("Export cost data as CSV")
                }
            }
            Divider()

            // Tab bar
            HStack(spacing: 0) {
                ForEach(DashboardTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tabIcon(tab))
                                .font(.system(size: 11))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(selectedTab == tab ? .forgeAmber : .secondary)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Rectangle()
                                .fill(Color.forgeAmber)
                                .frame(height: 2)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            Divider()

            if isLoading && costEntries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selectedTab {
                case .costs:
                    costsTabContent
                case .tasks:
                    tasksTabContent
                case .performance:
                    performanceTabContent
                case .efficiency:
                    efficiencyTabContent
                case .budgets:
                    budgetsTabContent
                }
            }
        }
        .task {
            await observeCosts()
        }
        .task {
            await observeTaskStatistics()
        }
        .task {
            await observeBackendScores()
        }
        .task {
            await observeBudgets()
        }
    }

    private func tabIcon(_ tab: DashboardTab) -> String {
        switch tab {
        case .costs: return "dollarsign.circle"
        case .tasks: return "chart.bar"
        case .performance: return "bolt"
        case .efficiency: return "gauge.with.needle"
        case .budgets: return "creditcard"
        }
    }

    // MARK: - Costs Tab

    private var costsTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary header
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Cost")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text(String(format: "$%.4f", totalCost))
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .forgeAmber)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invocations")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text("\(costEntries.count)")
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .forgeInfo)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Tokens")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        let totalTokens = costEntries.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
                        Text(formatTokenCount(totalTokens))
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .agentCoder)
                }

                if let errorMessage {
                    ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                }

                // Cost by agent type
                VStack(alignment: .leading, spacing: 8) {
                    Text("By Agent Type")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    ForEach(AgentTask.AgentType.allCases, id: \.self) { agentType in
                        let cost = costByAgent[agentType] ?? 0
                        if cost > 0 {
                            HStack(spacing: 8) {
                                AgentTypeBadge(type: agentType)
                                Spacer()

                                let maxCost = costByAgent.values.max() ?? 1
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(agentType.themeColor.opacity(0.3))
                                        .frame(width: geo.size.width * CGFloat(cost / maxCost))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .frame(width: 100, height: 8)

                                Text(String(format: "$%.4f", cost))
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(12)
                .forgeCard(cornerRadius: 8)

                // Recent entries
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Activity")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    if costEntries.isEmpty {
                        ForgeEmptyState(
                            icon: "dollarsign.circle",
                            title: "No Cost Entries",
                            subtitle: "Cost data will appear here as agents process tasks"
                        )
                        .frame(height: 120)
                    } else {
                        if costEntries.count > visibleCount {
                            Text("Showing \(visibleCount) of \(costEntries.count) entries")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }

                        ForEach(costEntries.prefix(visibleCount), id: \.id) { entry in
                            HStack(spacing: 8) {
                                AgentTypeBadge(type: entry.agentType)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(entry.inputTokens + entry.outputTokens) tokens")
                                        .font(.footnote)
                                    Text(entry.model)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Text(String(format: "$%.4f", entry.costUSD))
                                    .font(.system(.footnote, design: .monospaced))

                                Text(entry.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 3)

                            if entry.id != costEntries.prefix(visibleCount).last?.id {
                                Divider()
                            }
                        }

                        if costEntries.count > visibleCount {
                            Button {
                                visibleCount += 20
                            } label: {
                                Text("Load more...")
                                    .font(.footnote)
                                    .foregroundStyle(.forgeAmber)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(12)
                .forgeCard(cornerRadius: 8)
            }
            .padding(16)
        }
    }

    // MARK: - Tasks Tab

    private var tasksTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // KPI cards
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Tasks")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text("\(totalTasks)")
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .forgeInfo)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Success Rate")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text(String(format: "%.1f%%", successRate))
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .forgeSuccess)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Needs Revision")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        let revisionCount = tasksByAgent.reduce(0) { $0 + $1.needsRevision }
                        Text("\(revisionCount)")
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .forgeWarning)
                }

                // Bar chart: passed vs failed by agent
                VStack(alignment: .leading, spacing: 8) {
                    Text("Success vs Failure by Agent")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    if tasksByAgent.isEmpty {
                        Text("No task data")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    } else {
                        let maxTotal = tasksByAgent.map(\.total).max() ?? 1
                        ForEach(tasksByAgent, id: \.agentType) { agent in
                            HStack(spacing: 8) {
                                Text(agent.agentType.rawValue.capitalized)
                                    .font(.system(size: 11))
                                    .frame(width: 90, alignment: .leading)
                                    .lineLimit(1)

                                GeometryReader { geo in
                                    HStack(spacing: 1) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.forgeSuccess.opacity(0.6))
                                            .frame(width: geo.size.width * CGFloat(agent.passed) / CGFloat(maxTotal))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.forgeDanger.opacity(0.6))
                                            .frame(width: geo.size.width * CGFloat(agent.failed) / CGFloat(maxTotal))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.forgeWarning.opacity(0.6))
                                            .frame(width: geo.size.width * CGFloat(agent.needsRevision) / CGFloat(maxTotal))
                                    }
                                }
                                .frame(height: 12)

                                Text("\(agent.total)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }

                        HStack(spacing: 12) {
                            legendDot(color: .forgeSuccess, label: "Passed")
                            legendDot(color: .forgeDanger, label: "Failed")
                            legendDot(color: .forgeWarning, label: "Revision")
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(12)
                .forgeCard(cornerRadius: 8)

                // Table
                VStack(alignment: .leading, spacing: 8) {
                    Text("By Agent Type")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    if tasksByAgent.isEmpty {
                        Text("No data")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    } else {
                        // Header
                        HStack(spacing: 0) {
                            Text("Agent").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Total").frame(width: 50, alignment: .trailing)
                            Text("Pass").frame(width: 50, alignment: .trailing)
                            Text("Fail").frame(width: 50, alignment: .trailing)
                            Text("Rev").frame(width: 50, alignment: .trailing)
                            Text("Rate").frame(width: 60, alignment: .trailing)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)

                        ForEach(tasksByAgent, id: \.agentType) { agent in
                            let completed = agent.passed + agent.failed
                            let rate = completed > 0 ? Double(agent.passed) / Double(completed) * 100 : 0
                            HStack(spacing: 0) {
                                Text(agent.agentType.rawValue.capitalized)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(agent.total)").frame(width: 50, alignment: .trailing)
                                Text("\(agent.passed)")
                                    .foregroundStyle(.forgeSuccess)
                                    .frame(width: 50, alignment: .trailing)
                                Text("\(agent.failed)")
                                    .foregroundStyle(.forgeDanger)
                                    .frame(width: 50, alignment: .trailing)
                                Text("\(agent.needsRevision)")
                                    .foregroundStyle(.forgeWarning)
                                    .frame(width: 50, alignment: .trailing)
                                Text(String(format: "%.0f%%", rate))
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(12)
                .forgeCard(cornerRadius: 8)
            }
            .padding(16)
        }
    }

    // MARK: - Performance Tab

    private var performanceTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // KPI cards
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avg Duration")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text(formatDuration(avgDurationMs))
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .forgeInfo)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tasks/Day (7d)")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        let last7 = dailyCompleted.suffix(7)
                        let velocity = last7.isEmpty ? 0.0 : Double(last7.reduce(0) { $0 + $1.count }) / 7.0
                        Text(String(format: "%.1f", velocity))
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .forgeSuccess)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fastest Agent")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        let fastest = tasksByAgent.filter { $0.avgDurationMs != nil }.min(by: { ($0.avgDurationMs ?? .infinity) < ($1.avgDurationMs ?? .infinity) })
                        Text(fastest?.agentType.rawValue.capitalized ?? "—")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .forgeAmber)
                }

                // Avg duration by agent
                VStack(alignment: .leading, spacing: 8) {
                    Text("Avg Duration by Agent")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    let agentsWithDuration = tasksByAgent.filter { $0.avgDurationMs != nil }
                    if agentsWithDuration.isEmpty {
                        Text("No data")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    } else {
                        let maxDur = agentsWithDuration.compactMap(\.avgDurationMs).max() ?? 1
                        ForEach(agentsWithDuration, id: \.agentType) { agent in
                            HStack(spacing: 8) {
                                Text(agent.agentType.rawValue.capitalized)
                                    .font(.system(size: 11))
                                    .frame(width: 90, alignment: .leading)
                                    .lineLimit(1)

                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(agent.agentType.themeColor.opacity(0.5))
                                        .frame(width: geo.size.width * CGFloat((agent.avgDurationMs ?? 0) / maxDur))
                                }
                                .frame(height: 10)

                                Text(formatDuration(agent.avgDurationMs))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(12)
                .forgeCard(cornerRadius: 8)

                // Daily completed
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tasks Completed (Last 30 Days)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    if dailyCompleted.isEmpty {
                        Text("No completions in the last 30 days")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    } else {
                        let maxCount = dailyCompleted.map(\.count).max() ?? 1
                        // Bar chart
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(dailyCompleted, id: \.date) { day in
                                let height = CGFloat(day.count) / CGFloat(maxCount)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.forgeSuccess.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: max(height * 80, 2))
                                    .help("\(day.date): \(day.count) tasks")
                            }
                        }
                        .frame(height: 80)

                        // Table
                        ForEach(dailyCompleted.reversed(), id: \.date) { day in
                            HStack {
                                Text(day.date)
                                    .font(.system(size: 12))
                                Spacer()
                                Text("\(day.count)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(12)
                .forgeCard(cornerRadius: 8)
            }
            .padding(16)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(0.6)).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private func formatDuration(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        if ms < 1000 { return String(format: "%.0fms", ms) }
        if ms < 60000 { return String(format: "%.1fs", ms / 1000) }
        return String(format: "%.1fm", ms / 60000)
    }

    private func observeCosts() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try CostTracking
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
        do {
            for try await entries in observation.values(in: db.dbQueue) {
                costEntries = entries
                totalCost = entries.reduce(0) { $0 + $1.costUSD }
                costByAgent = Dictionary(grouping: entries, by: \.agentType)
                    .mapValues { $0.reduce(0) { $0 + $1.costUSD } }
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func observeTaskStatistics() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try AgentTask.fetchAll(db)
        }
        do {
            for try await tasks in observation.values(in: db.dbQueue) {
                let grouped = Dictionary(grouping: tasks, by: \.agentType)
                tasksByAgent = grouped.map { agentType, agentTasks in
                    let passed = agentTasks.filter { $0.status == .passed }.count
                    let failed = agentTasks.filter { $0.status == .failed }.count
                    let needsRevision = agentTasks.filter { $0.status == .needsRevision }.count
                    let durations = agentTasks.compactMap(\.durationMs)
                    let avgDur: Double? = durations.isEmpty ? nil : Double(durations.reduce(0, +)) / Double(durations.count)
                    return (agentType: agentType, total: agentTasks.count, passed: passed, failed: failed, needsRevision: needsRevision, avgDurationMs: avgDur)
                }.sorted { $0.total > $1.total }

                totalTasks = tasks.count
                let completed = tasks.filter { $0.status == .passed || $0.status == .failed }
                let passedCount = tasks.filter { $0.status == .passed }.count
                successRate = completed.isEmpty ? 0 : Double(passedCount) / Double(completed.count) * 100

                let allDurations = tasks.compactMap(\.durationMs)
                avgDurationMs = allDurations.isEmpty ? nil : Double(allDurations.reduce(0, +)) / Double(allDurations.count)

                // Daily completed (last 30 days)
                let calendar = Calendar.current
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let now = Date()
                let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
                let completedTasks = tasks.filter { ($0.status == .passed || $0.status == .failed) && $0.updatedAt >= thirtyDaysAgo }
                let byDay = Dictionary(grouping: completedTasks) { dateFormatter.string(from: $0.updatedAt) }
                var daily: [(date: String, count: Int)] = []
                for dayOffset in 0..<30 {
                    let date = calendar.date(byAdding: .day, value: -29 + dayOffset, to: now)!
                    let key = dateFormatter.string(from: date)
                    daily.append((date: key, count: byDay[key]?.count ?? 0))
                }
                dailyCompleted = daily
            }
        } catch { /* observation error */ }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "creedflow-costs.csv"
        panel.title = "Export Cost Data"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let dateFormatter = ISO8601DateFormatter()
        var csv = "Date,Agent Type,Model,Input Tokens,Output Tokens,Cost USD,Task ID\n"
        for entry in costEntries {
            let date = dateFormatter.string(from: entry.createdAt)
            let taskId = entry.taskId?.uuidString ?? ""
            csv += "\(date),\(entry.agentType.rawValue),\(entry.model),\(entry.inputTokens),\(entry.outputTokens),\(entry.costUSD),\(taskId)\n"
        }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    // MARK: - Efficiency Tab

    private var efficiencyTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if backendScores.isEmpty {
                    ForgeEmptyState(
                        icon: "gauge.with.needle",
                        title: "No Score Data",
                        subtitle: "Backend scores are computed every 5 minutes after tasks complete"
                    )
                    .frame(height: 200)
                } else {
                    ForEach(backendScores.sorted(by: { $0.compositeScore > $1.compositeScore }), id: \.id) { score in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(score.backendType.displayName)
                                    .font(.headline)
                                Spacer()
                                backendScoreBadge(score.compositeScore)
                                Text("\(score.sampleSize) tasks")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            scoreDimensionBar(label: "Cost Efficiency", value: score.costEfficiency, color: .green)
                            scoreDimensionBar(label: "Speed", value: score.speed, color: .blue)
                            scoreDimensionBar(label: "Reliability", value: score.reliability, color: .orange)
                            scoreDimensionBar(label: "Quality", value: score.quality, color: .purple)
                        }
                        .padding(12)
                        .forgeCard(cornerRadius: 8)
                    }
                }
            }
            .padding(16)
        }
    }

    private func scoreDimensionBar(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 100, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.6))
                        .frame(width: geo.size.width * CGFloat(min(value, 1.0)), height: 8)
                }
            }
            .frame(height: 8)

            Text(String(format: "%.0f", value * 100))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func backendScoreBadge(_ score: Double) -> some View {
        let pct = Int(score * 100)
        let color: Color = pct >= 70 ? .green : pct >= 40 ? .orange : .red
        return Text("\(pct)")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Budgets Tab

    private var budgetsTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Cost Budgets")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editingBudget = nil
                        showBudgetForm = true
                    } label: {
                        Label("Add Budget", systemImage: "plus")
                            .font(.system(size: 12))
                    }
                }

                if costBudgets.isEmpty {
                    ForgeEmptyState(
                        icon: "creditcard",
                        title: "No Budgets",
                        subtitle: "Create a budget to track and limit AI spending"
                    )
                    .frame(height: 150)
                } else {
                    ForEach(costBudgets, id: \.id) { budget in
                        budgetCard(budget)
                    }
                }

                // Recent alerts
                if !budgetAlerts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Alerts")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        ForEach(budgetAlerts.prefix(10), id: \.id) { alert in
                            HStack(spacing: 8) {
                                Image(systemName: alert.thresholdType == .warn ? "exclamationmark.triangle" : "xmark.octagon")
                                    .foregroundStyle(alert.thresholdType == .warn ? .orange : .red)
                                    .font(.system(size: 12))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(alert.thresholdType.rawValue.capitalized) — \(Int(alert.percentage * 100))%")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("$\(String(format: "%.2f", alert.currentSpend)) / $\(String(format: "%.2f", alert.limitUsd))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(alert.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(12)
                    .forgeCard(cornerRadius: 8)
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showBudgetForm) {
            BudgetFormView(appDatabase: appDatabase, existingBudget: editingBudget) {
                showBudgetForm = false
            }
        }
    }

    private func budgetCard(_ budget: CostBudget) -> some View {
        let spending = budgetSpending[budget.id] ?? 0
        let percentage = budget.limitUsd > 0 ? spending / budget.limitUsd : 0
        let barColor: Color = percentage >= 1.0 ? .red : percentage >= budget.criticalThreshold ? .orange : percentage >= budget.warnThreshold ? .yellow : .green

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(budget.scope == .global ? "Global" : "Project")
                            .font(.system(size: 12, weight: .semibold))
                        Text(budget.period.rawValue.capitalized)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text("$\(String(format: "%.2f", spending)) / $\(String(format: "%.2f", budget.limitUsd))")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                }
                Spacer()
                Text("\(Int(percentage * 100))%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(barColor)
            }

            // Utilization bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.05))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor.opacity(0.6))
                        .frame(width: geo.size.width * CGFloat(min(percentage, 1.0)))
                }
            }
            .frame(height: 10)

            HStack(spacing: 12) {
                if budget.pauseOnExceed {
                    Label("Auto-pause", systemImage: "pause.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    editingBudget = budget
                    showBudgetForm = true
                } label: {
                    Text("Edit")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.forgeAmber)

                Button {
                    Task { await deleteBudget(budget) }
                } label: {
                    Text("Delete")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .forgeCard(cornerRadius: 8)
    }

    // MARK: - Budget CRUD

    private func deleteBudget(_ budget: CostBudget) async {
        guard let db = appDatabase else { return }
        do {
            try await db.dbQueue.write { db in
                try CostBudget.deleteOne(db, id: budget.id)
            }
        } catch {
            errorMessage = "Failed to delete budget: \(error.localizedDescription)"
        }
    }

    // MARK: - Observations (Scores + Budgets)

    private func observeBackendScores() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try BackendScore.fetchAll(db)
        }
        do {
            for try await scores in observation.values(in: db.dbQueue) {
                backendScores = scores
            }
        } catch { /* observation error */ }
    }

    private func observeBudgets() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { dbConn in
            try CostBudget.order(Column("createdAt").desc).fetchAll(dbConn)
        }
        do {
            for try await budgets in observation.values(in: db.dbQueue) {
                costBudgets = budgets
                // Compute spending and alerts in a separate read
                let (spending, alerts) = try await db.dbQueue.read { dbConn -> ([UUID: Double], [BudgetAlert]) in
                    var spendMap: [UUID: Double] = [:]
                    for budget in budgets {
                        let periodStart = Self.periodStartDate(for: budget.period)
                        var sql = "SELECT COALESCE(SUM(costUSD), 0) FROM costTracking WHERE createdAt >= ?"
                        var args: [DatabaseValueConvertible] = [periodStart]
                        if budget.scope == .project, let pid = budget.projectId {
                            sql += " AND projectId = ?"
                            args.append(pid.uuidString)
                        }
                        if let amount = try Double.fetchOne(dbConn, sql: sql, arguments: StatementArguments(args)) {
                            spendMap[budget.id] = amount
                        }
                    }
                    let recentAlerts = try BudgetAlert.order(Column("createdAt").desc).limit(20).fetchAll(dbConn)
                    return (spendMap, recentAlerts)
                }
                budgetSpending = spending
                budgetAlerts = alerts
            }
        } catch { /* observation error */ }
    }

    private static func periodStartDate(for period: CostBudget.Period) -> Date {
        let calendar = Calendar.current
        let now = Date()
        switch period {
        case .daily:
            return calendar.startOfDay(for: now)
        case .weekly:
            let weekday = calendar.component(.weekday, from: now)
            return calendar.date(byAdding: .day, value: -(weekday - calendar.firstWeekday), to: calendar.startOfDay(for: now))!
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: now)
            return calendar.date(from: components)!
        }
    }
}

// MARK: - Budget Form

struct BudgetFormView: View {
    let appDatabase: AppDatabase?
    let existingBudget: CostBudget?
    let onDismiss: () -> Void

    @State private var scope: CostBudget.Scope = .global
    @State private var period: CostBudget.Period = .monthly
    @State private var limitUsd: Double = 50.0
    @State private var warnThreshold: Double = 80
    @State private var criticalThreshold: Double = 95
    @State private var pauseOnExceed = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text(existingBudget != nil ? "Edit Budget" : "New Budget")
                .font(.headline)

            Form {
                Picker("Scope", selection: $scope) {
                    ForEach(CostBudget.Scope.allCases, id: \.self) { s in
                        Text(s.rawValue.capitalized).tag(s)
                    }
                }

                Picker("Period", selection: $period) {
                    ForEach(CostBudget.Period.allCases, id: \.self) { p in
                        Text(p.rawValue.capitalized).tag(p)
                    }
                }

                HStack {
                    Text("Limit ($)")
                    Spacer()
                    TextField("Amount", value: $limitUsd, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack {
                    Text("Warn at (%)")
                    Spacer()
                    TextField("", value: $warnThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }

                HStack {
                    Text("Critical at (%)")
                    Spacer()
                    TextField("", value: $criticalThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }

                Toggle("Pause tasks when exceeded", isOn: $pauseOnExceed)
            }
            .formStyle(.grouped)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(existingBudget != nil ? "Save" : "Create") {
                    Task { await saveBudget() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let b = existingBudget {
                scope = b.scope
                period = b.period
                limitUsd = b.limitUsd
                warnThreshold = b.warnThreshold * 100
                criticalThreshold = b.criticalThreshold * 100
                pauseOnExceed = b.pauseOnExceed
            }
        }
    }

    private func saveBudget() async {
        guard let db = appDatabase else { return }
        do {
            try await db.dbQueue.write { db in
                if var existing = existingBudget {
                    existing.scope = scope
                    existing.period = period
                    existing.limitUsd = limitUsd
                    existing.warnThreshold = warnThreshold / 100
                    existing.criticalThreshold = criticalThreshold / 100
                    existing.pauseOnExceed = pauseOnExceed
                    existing.updatedAt = Date()
                    try existing.update(db)
                } else {
                    var budget = CostBudget(
                        scope: scope,
                        period: period,
                        limitUsd: limitUsd,
                        warnThreshold: warnThreshold / 100,
                        criticalThreshold: criticalThreshold / 100,
                        pauseOnExceed: pauseOnExceed
                    )
                    try budget.insert(db)
                }
            }
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
