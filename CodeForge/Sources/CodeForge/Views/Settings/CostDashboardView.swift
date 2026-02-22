import SwiftUI
import GRDB

struct CostDashboardView: View {
    let appDatabase: AppDatabase?
    @State private var costEntries: [CostTracking] = []
    @State private var totalCost: Double = 0
    @State private var costByAgent: [AgentTask.AgentType: Double] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Total cost
                HStack {
                    VStack(alignment: .leading) {
                        Text("Total Cost")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "$%.4f", totalCost))
                            .font(.largeTitle.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(costEntries.count)")
                            .font(.title2.bold())
                    }
                }
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Cost by agent type
                GroupBox("Cost by Agent Type") {
                    ForEach(AgentTask.AgentType.allCases, id: \.self) { agentType in
                        let cost = costByAgent[agentType] ?? 0
                        if cost > 0 {
                            HStack {
                                AgentTypeBadge(type: agentType)
                                Spacer()
                                Text(String(format: "$%.4f", cost))
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Recent entries
                GroupBox("Recent Costs") {
                    ForEach(costEntries.prefix(20)) { entry in
                        HStack {
                            AgentTypeBadge(type: entry.agentType)
                            VStack(alignment: .leading) {
                                Text("\(entry.inputTokens + entry.outputTokens) tokens")
                                    .font(.caption)
                                Text(entry.model)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "$%.4f", entry.costUSD))
                                .font(.system(.caption, design: .monospaced))
                            Text(entry.createdAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Costs")
        .task { await loadCosts() }
    }

    private func loadCosts() async {
        guard let db = appDatabase else { return }
        do {
            costEntries = try await db.dbQueue.read { db in
                try CostTracking
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }

            totalCost = costEntries.reduce(0) { $0 + $1.costUSD }

            costByAgent = Dictionary(grouping: costEntries, by: \.agentType)
                .mapValues { entries in entries.reduce(0) { $0 + $1.costUSD } }
        } catch {}
    }
}
