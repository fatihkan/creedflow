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

    private enum DashboardTab: String, CaseIterable {
        case costs = "Costs"
        case tasks = "Tasks"
        case performance = "Performance"
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
                }
            }
        }
        .task {
            await observeCosts()
        }
        .task {
            await observeTaskStatistics()
        }
    }

    private func tabIcon(_ tab: DashboardTab) -> String {
        switch tab {
        case .costs: return "dollarsign.circle"
        case .tasks: return "chart.bar"
        case .performance: return "bolt"
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
}
