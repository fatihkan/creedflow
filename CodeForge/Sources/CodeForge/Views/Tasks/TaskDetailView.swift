import SwiftUI
import GRDB

struct TaskDetailView: View {
    let taskId: UUID
    let appDatabase: AppDatabase?
    let orchestrator: Orchestrator?

    @State private var task: AgentTask?
    @State private var reviews: [Review] = []
    @State private var showTerminal = true

    var body: some View {
        ScrollView {
            if let task {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        AgentTypeBadge(type: task.agentType)
                        StatusBadge(status: task.status.rawValue)
                        Spacer()
                        Text("P\(task.priority)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    Text(task.title)
                        .font(.title2.bold())

                    Text(task.description)
                        .foregroundStyle(.secondary)

                    // Metadata
                    GroupBox("Details") {
                        LabeledContent("Agent", value: task.agentType.rawValue)
                        if let branch = task.branchName {
                            LabeledContent("Branch", value: branch)
                        }
                        if let pr = task.prNumber {
                            LabeledContent("PR", value: "#\(pr)")
                        }
                        if let cost = task.costUSD {
                            LabeledContent("Cost", value: String(format: "$%.4f", cost))
                        }
                        if let duration = task.durationMs {
                            LabeledContent("Duration", value: "\(duration / 1000)s")
                        }
                        LabeledContent("Retries", value: "\(task.retryCount)/\(task.maxRetries)")
                    }

                    // Live terminal output
                    if task.status == .inProgress, let runner = orchestrator?.runner(for: taskId) {
                        DisclosureGroup("Agent Console", isExpanded: $showTerminal) {
                            TerminalOutputView(runner: runner)
                                .frame(minHeight: 300)
                        }
                    }

                    // Error
                    if let error = task.errorMessage {
                        GroupBox("Error") {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    // Reviews
                    if !reviews.isEmpty {
                        GroupBox("Reviews") {
                            ForEach(reviews) { review in
                                ReviewRowView(review: review)
                            }
                        }
                    }

                    // Actions
                    HStack {
                        if task.status == .failed {
                            Button("Retry") {
                                Task { await retryTask() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if task.status == .inProgress {
                            Button("Cancel") {
                                Task { await cancelTask() }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        guard let db = appDatabase else { return }
        do {
            task = try await db.dbQueue.read { db in
                try AgentTask.fetchOne(db, id: taskId)
            }
            reviews = try await db.dbQueue.read { db in
                try Review
                    .filter(Column("taskId") == taskId)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
        } catch {}
    }

    private func retryTask() async {
        guard let db = appDatabase, var task else { return }
        do {
            try await db.dbQueue.write { dbConn in
                task.status = .queued
                task.retryCount += 1
                task.errorMessage = nil
                task.updatedAt = Date()
                try task.update(dbConn)
            }
        } catch {}
    }

    private func cancelTask() async {
        guard let db = appDatabase, var task else { return }
        do {
            try await db.dbQueue.write { dbConn in
                task.status = .cancelled
                task.updatedAt = Date()
                task.completedAt = Date()
                try task.update(dbConn)
            }
        } catch {}
    }
}

struct ReviewRowView: View {
    let review: Review

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(review.verdict.rawValue.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(review.verdict == .pass ? .green : review.verdict == .needsRevision ? .orange : .red)
                Text(String(format: "%.1f/10", review.score))
                    .font(.caption)
                Spacer()
                Text(review.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(review.summary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
