import SwiftUI
import GRDB

/// Velocity-based projected completion estimate widget.
struct ProjectForecastView: View {
    let projectId: UUID
    let appDatabase: AppDatabase?

    @State private var forecast: Forecast?

    struct Forecast {
        let totalTasks: Int
        let completedTasks: Int
        let remainingTasks: Int
        let velocity7Day: Double        // tasks/day over last 7 days
        let velocity30Day: Double       // tasks/day over last 30 days
        let estimatedDaysLow: Double?   // optimistic (7-day velocity)
        let estimatedDaysHigh: Double?  // conservative (30-day velocity)
        let completionPct: Double       // 0..1
    }

    var body: some View {
        if let f = forecast, f.totalTasks > 0 {
            DisclosureGroup("Projected Completion") {
                VStack(alignment: .leading, spacing: 8) {
                    // Progress bar
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(f.completedTasks)/\(f.totalTasks) tasks")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((f.completionPct * 100).rounded()))%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.forgeAmber)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.quaternary)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.forgeAmber)
                                    .frame(width: geo.size.width * f.completionPct, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }

                    // Velocity stats
                    HStack(spacing: 12) {
                        velocityStat(label: "7-day", value: f.velocity7Day)
                        velocityStat(label: "30-day", value: f.velocity30Day)
                    }

                    // Estimated completion
                    if f.remainingTasks > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 12))
                                .foregroundStyle(.forgeInfo)

                            if let low = f.estimatedDaysLow, let high = f.estimatedDaysHigh {
                                if low == high || abs(low - high) < 1 {
                                    Text("~\(formatDays(low))")
                                        .font(.system(size: 12, weight: .medium))
                                } else {
                                    Text("\(formatDays(low)) – \(formatDays(high))")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            } else if let low = f.estimatedDaysLow {
                                Text("~\(formatDays(low))")
                                    .font(.system(size: 12, weight: .medium))
                            } else {
                                Text("Insufficient data")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.forgeSuccess)
                            Text("All tasks complete")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.forgeSuccess)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.subheadline.bold())
        }
    }

    private func velocityStat(label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(String(format: "%.1f/day", value))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(value > 0 ? .forgeSuccess : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formatDays(_ days: Double) -> String {
        if days < 1 { return "< 1 day" }
        if days < 2 { return "1 day" }
        if days < 7 { return "\(Int(days.rounded())) days" }
        let weeks = days / 7.0
        if weeks < 2 { return "1 week" }
        return String(format: "%.1f weeks", weeks)
    }

    // MARK: - Modifiers

    func loadForecast() -> some View {
        self.task(id: projectId) {
            await computeForecast()
        }
    }

    private func computeForecast() async {
        guard let db = appDatabase else { return }
        do {
            let f = try await db.dbQueue.read { db -> Forecast in
                let totalTasks = try AgentTask
                    .filter(Column("projectId") == projectId)
                    .filter(Column("archivedAt") == nil)
                    .fetchCount(db)

                let completedTasks = try AgentTask
                    .filter(Column("projectId") == projectId)
                    .filter(Column("archivedAt") == nil)
                    .filter(Column("status") == "passed")
                    .fetchCount(db)

                let remainingTasks = totalTasks - completedTasks

                // 7-day velocity: tasks completed in last 7 days
                let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                let completed7 = try AgentTask
                    .filter(Column("projectId") == projectId)
                    .filter(Column("archivedAt") == nil)
                    .filter(Column("status") == "passed")
                    .filter(Column("completedAt") >= sevenDaysAgo)
                    .fetchCount(db)
                let velocity7 = Double(completed7) / 7.0

                // 30-day velocity
                let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
                let completed30 = try AgentTask
                    .filter(Column("projectId") == projectId)
                    .filter(Column("archivedAt") == nil)
                    .filter(Column("status") == "passed")
                    .filter(Column("completedAt") >= thirtyDaysAgo)
                    .fetchCount(db)
                let velocity30 = Double(completed30) / 30.0

                let estLow = velocity7 > 0 ? Double(remainingTasks) / velocity7 : nil
                let estHigh = velocity30 > 0 ? Double(remainingTasks) / velocity30 : nil

                let completionPct = totalTasks > 0 ? Double(completedTasks) / Double(totalTasks) : 0

                return Forecast(
                    totalTasks: totalTasks,
                    completedTasks: completedTasks,
                    remainingTasks: remainingTasks,
                    velocity7Day: velocity7,
                    velocity30Day: velocity30,
                    estimatedDaysLow: estLow,
                    estimatedDaysHigh: estHigh,
                    completionPct: completionPct
                )
            }
            forecast = f
        } catch {
            // silently fail
        }
    }
}
