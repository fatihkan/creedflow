import SwiftUI
import GRDB

struct ReviewApprovalView: View {
    let appDatabase: AppDatabase?
    @State private var pendingReviews: [(review: Review, task: AgentTask, project: Project)] = []
    @State private var errorMessage: String?
    @State private var taskToReject: AgentTask?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Reviews")
            Divider()

            if isLoading && pendingReviews.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pendingReviews.isEmpty && errorMessage == nil {
                ForgeEmptyState(
                    icon: "checkmark.shield",
                    title: "All Clear",
                    subtitle: "All reviews have been processed. New reviews will appear here when ready."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if let errorMessage {
                            ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                        }

                        ForEach(pendingReviews, id: \.review.id) { item in
                            reviewCard(item: item)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task {
            await observeReviews()
        }
        .confirmationDialog(
            "Reject Review",
            isPresented: Binding(
                get: { taskToReject != nil },
                set: { if !$0 { taskToReject = nil } }
            ),
            presenting: taskToReject
        ) { task in
            Button("Reject \"\(task.title)\"", role: .destructive) {
                Task { await reject(task) }
            }
        } message: { task in
            Text("This will mark \"\(task.title)\" as failed. The task will need to be manually retried.")
        }
    }

    private func reviewCard(item: (review: Review, task: AgentTask, project: Project)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.task.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(item.review.verdict.rawValue.uppercased())
                    .forgeBadge(color: item.review.verdict == .pass ? .forgeSuccess :
                                item.review.verdict == .needsRevision ? .forgeWarning : .forgeDanger)
            }

            HStack(spacing: 6) {
                Text(item.project.name)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Score: \(String(format: "%.1f", item.review.score))/10")
                    .font(.system(.caption, design: .monospaced, weight: .medium))
            }

            Text(item.review.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Spacer()
                Button {
                    taskToReject = item.task
                } label: {
                    Label("Reject", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .tint(.forgeDanger)

                Button {
                    Task { await approve(item.task) }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.forgeSuccess)
            }
        }
        .padding(12)
        .forgeCard(cornerRadius: 8)
    }

    private func observeReviews() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            let reviews = try Review
                .filter(Column("verdict") != Review.Verdict.pass.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)

            return try reviews.compactMap { review -> (review: Review, task: AgentTask, project: Project)? in
                guard let task = try AgentTask.fetchOne(db, id: review.taskId),
                      let project = try Project.fetchOne(db, id: task.projectId) else {
                    return nil
                }
                return (review: review, task: task, project: project)
            }
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                pendingReviews = value
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func approve(_ task: AgentTask) async {
        guard let db = appDatabase else { return }
        do {
            try await db.dbQueue.write { dbConn in
                var updated = task
                updated.status = .passed
                updated.updatedAt = Date()
                try updated.update(dbConn)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reject(_ task: AgentTask) async {
        guard let db = appDatabase else { return }
        do {
            try await db.dbQueue.write { dbConn in
                var updated = task
                updated.status = .failed
                updated.errorMessage = "Rejected by reviewer"
                updated.updatedAt = Date()
                updated.completedAt = Date()
                try updated.update(dbConn)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
