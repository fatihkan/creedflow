import SwiftUI
import GRDB

struct CostDashboardView: View {
    let appDatabase: AppDatabase?

    @State private var costEntries: [CostTracking] = []
    @State private var totalCost: Double = 0
    @State private var costByAgent: [AgentTask.AgentType: Double] = [:]
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary header
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Cost")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(String(format: "$%.4f", totalCost))
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .forgeAmber)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invocations")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("\(costEntries.count)")
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                    .forgeMetricCard(accent: .forgeInfo)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Tokens")
                            .font(.system(size: 10))
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

                                // Bar proportional to max cost
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
                        ForEach(costEntries.prefix(20)) { entry in
                            HStack(spacing: 8) {
                                AgentTypeBadge(type: entry.agentType)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(entry.inputTokens + entry.outputTokens) tokens")
                                        .font(.caption)
                                    Text(entry.model)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Text(String(format: "$%.4f", entry.costUSD))
                                    .font(.system(.caption, design: .monospaced))

                                Text(entry.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 3)

                            if entry.id != costEntries.prefix(20).last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .padding(12)
                .forgeCard(cornerRadius: 8)
            }
            .padding(16)
        }
        .navigationTitle("Costs")
        .task {
            await observeCosts()
        }
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
            }
        } catch {
            errorMessage = error.localizedDescription
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
