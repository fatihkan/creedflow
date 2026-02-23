import SwiftUI
import GRDB

struct TaskDetailView: View {
    let taskId: UUID
    let appDatabase: AppDatabase?
    let orchestrator: Orchestrator?
    var onDismiss: (() -> Void)?

    @State private var task: AgentTask?
    @State private var reviews: [Review] = []
    @State private var logs: [AgentLog] = []
    @State private var showTerminal = true
    @State private var errorMessage: String?
    @State private var showCancelConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header bar (outside ScrollView so close button always works)
            if let task {
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: task.agentType.icon)
                        Text(task.agentType.rawValue.capitalized)
                    }
                    .forgeBadge(color: task.agentType.themeColor)

                    Text(task.status.displayName)
                        .forgeBadge(color: task.status.themeColor)

                    if task.priority > 0 {
                        Text("P\(task.priority)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.forgeAmber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.forgeAmber.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text(task.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    if let onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.background)

                Divider()
            }

        ScrollView {
            if let task {
                VStack(alignment: .leading, spacing: 12) {
                    Text(task.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Metadata grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 8) {
                        if let branch = task.branchName {
                            metadataItem(label: "Branch", value: branch, icon: "arrow.triangle.branch")
                        }
                        if let pr = task.prNumber {
                            metadataItem(label: "PR", value: "#\(pr)", icon: "arrow.triangle.pull")
                        }
                        if let cost = task.costUSD {
                            metadataItem(label: "Cost", value: String(format: "$%.4f", cost), icon: "dollarsign.circle")
                        }
                        if let duration = task.durationMs {
                            metadataItem(label: "Duration", value: ForgeDuration.format(ms: duration), icon: "clock")
                        }
                        metadataItem(label: "Retries", value: "\(task.retryCount)/\(task.maxRetries)", icon: "arrow.counterclockwise")
                        if let sessionId = task.sessionId {
                            metadataItem(label: "Session", value: String(sessionId.prefix(8)), icon: "link")
                        }
                    }

                    // Live terminal / Historical output
                    if task.status == .inProgress, let runner = orchestrator?.runner(for: taskId) {
                        DisclosureGroup("Agent Console", isExpanded: $showTerminal) {
                            TerminalOutputView(runner: runner)
                                .frame(minHeight: 200)
                        }
                        .font(.subheadline.bold())
                    } else if !logs.isEmpty {
                        DisclosureGroup("Agent Logs (\(logs.count))", isExpanded: $showTerminal) {
                            if logs.count >= 200 {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle")
                                        .font(.caption2)
                                    Text("Showing last 200 entries. Older logs may be truncated.")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.forgeWarning)
                                .padding(.bottom, 4)
                            }
                            LogOutputView(logs: logs)
                                .frame(minHeight: 150)
                        }
                        .font(.subheadline.bold())
                    }

                    // Error display
                    if let error = task.errorMessage {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.forgeDanger)
                                Text("Error")
                                    .font(.subheadline.bold())
                            }
                            Text(error)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.forgeDanger)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.forgeDanger.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Reviews
                    if !reviews.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reviews")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            ForEach(reviews) { review in
                                ReviewRowView(review: review)
                            }
                        }
                    }

                    // Actions
                    HStack(spacing: 8) {
                        if task.status == .failed || task.status == .needsRevision {
                            Button {
                                Task { await retryTask() }
                            } label: {
                                Label("Retry", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.forgeAmber)
                        }
                        if task.status == .inProgress || task.status == .queued {
                            Button(role: .destructive) {
                                showCancelConfirm = true
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if let errorMessage {
                        ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                    }
                }
                .padding(16)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: taskId) {
            await observeData()
        }
        .confirmationDialog("Cancel Task", isPresented: $showCancelConfirm) {
            Button("Cancel Task", role: .destructive) {
                Task { await cancelTask() }
            }
        } message: {
            Text("This will stop the running agent and cancel the task. This cannot be undone.")
        }
        } // VStack
    }

    // MARK: - Metadata Item

    private func metadataItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Data Observation

    private func observeData() async {
        guard let db = appDatabase else { return }
        let tid = taskId
        let observation = ValueObservation.tracking { db -> (AgentTask?, [Review], [AgentLog]) in
            let task = try AgentTask.fetchOne(db, id: tid)
            let reviews = try Review
                .filter(Column("taskId") == tid)
                .order(Column("createdAt").desc)
                .fetchAll(db)
            let logs = try AgentLog
                .filter(Column("taskId") == tid)
                .order(Column("createdAt").asc)
                .limit(200)
                .fetchAll(db)
            return (task, reviews, logs)
        }
        do {
            for try await (t, r, l) in observation.values(in: db.dbQueue) {
                task = t
                reviews = r
                logs = l
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func retryTask() async {
        guard let db = appDatabase else { return }
        do {
            try await db.dbQueue.write { dbConn in
                guard var t = try AgentTask.fetchOne(dbConn, id: taskId) else { return }
                t.status = .queued
                t.retryCount += 1
                t.errorMessage = nil
                t.updatedAt = Date()
                try t.update(dbConn)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelTask() async {
        guard let db = appDatabase else { return }
        do {
            try await db.dbQueue.write { dbConn in
                guard var t = try AgentTask.fetchOne(dbConn, id: taskId) else { return }
                t.status = .cancelled
                t.updatedAt = Date()
                t.completedAt = Date()
                try t.update(dbConn)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Review Row

struct ReviewRowView: View {
    let review: Review

    var body: some View {
        HStack(spacing: 8) {
            Text(review.verdict.rawValue.uppercased())
                .forgeBadge(color: verdictColor)

            Text(String(format: "%.1f/10", review.score))
                .font(.system(.caption, design: .monospaced, weight: .medium))

            Text(review.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(review.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private var verdictColor: Color {
        switch review.verdict {
        case .pass: return .forgeSuccess
        case .needsRevision: return .forgeWarning
        case .fail: return .forgeDanger
        }
    }
}

// MARK: - Log Output View (Historical)

struct LogOutputView: View {
    let logs: [AgentLog]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(logs) { log in
                    HStack(alignment: .top, spacing: 6) {
                        Text(log.createdAt, format: .dateTime.hour().minute().second())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.forgeNeutral)
                            .frame(width: 60, alignment: .leading)

                        Text(log.level.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(logColor(for: log.level))
                            .frame(width: 36, alignment: .leading)

                        Text(log.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.forgeTerminalText)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(8)
        }
        .background(Color.forgeTerminalBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func logColor(for level: AgentLog.Level) -> Color {
        switch level {
        case .debug: return .forgeNeutral
        case .info: return .forgeTerminalCyan
        case .warning: return .forgeTerminalYellow
        case .error: return .forgeTerminalRed
        }
    }
}
