import SwiftUI
import GRDB

struct PromptEffectivenessDashboardView: View {
    let appDatabase: AppDatabase?

    @State private var prompts: [Prompt] = []
    @State private var stats: [UUID: PromptStats] = [:]
    @State private var isLoading = true

    private var totalUsages: Int {
        stats.values.reduce(0) { $0 + $1.usageCount }
    }

    private var avgSuccessRate: Double? {
        let rates = stats.values.compactMap(\.successRate)
        guard !rates.isEmpty else { return nil }
        return rates.reduce(0, +) / Double(rates.count)
    }

    private var avgReviewScore: Double? {
        let scores = stats.values.compactMap(\.averageReviewScore)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private var sortedPrompts: [(prompt: Prompt, stats: PromptStats)] {
        prompts.compactMap { prompt -> (Prompt, PromptStats)? in
            guard let s = stats[prompt.id], s.usageCount > 0 else { return nil }
            return (prompt, s)
        }
        .sorted { a, b in
            compositeScore(a.1) > compositeScore(b.1)
        }
    }

    var body: some View {
        Group {
            if isLoading && prompts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Metric cards
                        HStack(spacing: 16) {
                            MetricCard(
                                label: "Total Prompts",
                                value: "\(prompts.count)",
                                icon: "text.book.closed",
                                accent: .forgeAmber
                            )
                            MetricCard(
                                label: "Total Usages",
                                value: "\(totalUsages)",
                                icon: "chart.bar",
                                accent: .forgeInfo
                            )
                            MetricCard(
                                label: "Avg Success",
                                value: avgSuccessRate.map { "\(Int($0 * 100))%" } ?? "—",
                                icon: "checkmark.circle",
                                accent: .forgeSuccess
                            )
                            MetricCard(
                                label: "Avg Review",
                                value: avgReviewScore.map { String(format: "%.1f", $0) } ?? "—",
                                icon: "star.fill",
                                accent: .agentReviewer
                            )
                        }

                        // Effectiveness table
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prompts by Effectiveness")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)

                            if sortedPrompts.isEmpty {
                                ForgeEmptyState(
                                    icon: "chart.bar.doc.horizontal",
                                    title: "No Usage Data",
                                    subtitle: "Use prompts to see effectiveness metrics here"
                                )
                                .frame(height: 120)
                            } else {
                                let maxScore = sortedPrompts.map { compositeScore($0.stats) }.max() ?? 1

                                ForEach(sortedPrompts, id: \.prompt.id) { item in
                                    HStack(spacing: 10) {
                                        Text(item.prompt.title)
                                            .font(.footnote)
                                            .lineLimit(1)
                                            .frame(width: 140, alignment: .leading)

                                        GeometryReader { geo in
                                            let score = compositeScore(item.stats)
                                            let width = maxScore > 0 ? geo.size.width * CGFloat(score / maxScore) : 0
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(effectivenessColor(score).opacity(0.4))
                                                .frame(width: max(width, 2))
                                        }
                                        .frame(height: 8)

                                        Text("\(item.stats.usageCount)")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 30, alignment: .trailing)

                                        if let rate = item.stats.successRate {
                                            Text("\(Int(rate * 100))%")
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(rate >= 0.7 ? .forgeSuccess : rate >= 0.4 ? .forgeWarning : .forgeDanger)
                                                .frame(width: 36, alignment: .trailing)
                                        } else {
                                            Text("—")
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                                .frame(width: 36, alignment: .trailing)
                                        }

                                        if let score = item.stats.averageReviewScore {
                                            Text(String(format: "%.1f", score))
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(score >= 7.0 ? .forgeSuccess : score >= 5.0 ? .forgeWarning : .forgeDanger)
                                                .frame(width: 30, alignment: .trailing)
                                        } else {
                                            Text("—")
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                                .frame(width: 30, alignment: .trailing)
                                        }
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                        }
                        .padding(12)
                        .forgeCard(cornerRadius: 8)
                    }
                    .padding(16)
                }
            }
        }
        .task {
            await observeData()
        }
    }

    private func compositeScore(_ stats: PromptStats) -> Double {
        let rateComponent = (stats.successRate ?? 0.5) * 50
        let scoreComponent = ((stats.averageReviewScore ?? 5.0) / 10.0) * 30
        let usageComponent = min(Double(stats.usageCount) / 10.0, 1.0) * 20
        return rateComponent + scoreComponent + usageComponent
    }

    private func effectivenessColor(_ score: Double) -> Color {
        if score >= 70 { return .forgeSuccess }
        if score >= 40 { return .forgeWarning }
        return .forgeDanger
    }

    private func observeData() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db -> ([Prompt], [PromptUsage]) in
            let prompts = try Prompt.order(Column("title").asc).fetchAll(db)
            let usages = try PromptUsage.fetchAll(db)
            return (prompts, usages)
        }
        do {
            for try await (fetchedPrompts, usages) in observation.values(in: db.dbQueue) {
                prompts = fetchedPrompts
                var newStats: [UUID: PromptStats] = [:]
                let grouped = Dictionary(grouping: usages, by: \.promptId)
                for (promptId, records) in grouped {
                    let count = records.count
                    let withOutcome = records.filter { $0.outcome != nil }
                    let successRate: Double?
                    if !withOutcome.isEmpty {
                        let successes = withOutcome.filter { $0.outcome == .completed }.count
                        successRate = Double(successes) / Double(withOutcome.count)
                    } else {
                        successRate = nil
                    }
                    let scores = records.compactMap(\.reviewScore)
                    let avgScore = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
                    newStats[promptId] = PromptStats(usageCount: count, successRate: successRate, averageReviewScore: avgScore)
                }
                stats = newStats
                isLoading = false
            }
        } catch {
            isLoading = false
        }
    }
}
