import SwiftUI
import GRDB

struct ReviewApprovalView: View {
    let appDatabase: AppDatabase?
    @State private var pendingReviews: [(review: Review, task: AgentTask, project: Project)] = []

    var body: some View {
        List {
            if pendingReviews.isEmpty {
                ContentUnavailableView(
                    "No Pending Reviews",
                    systemImage: "checkmark.shield",
                    description: Text("Reviews requiring approval will appear here")
                )
            } else {
                ForEach(pendingReviews, id: \.review.id) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.task.title)
                                .font(.headline)
                            Spacer()
                            StatusBadge(status: item.review.verdict.rawValue)
                        }

                        Text(item.project.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(item.review.summary)
                            .font(.subheadline)

                        HStack {
                            Text(String(format: "Score: %.1f/10", item.review.score))
                                .font(.caption.bold())

                            Spacer()

                            Button("Approve") {
                                Task { await approve(item.task) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)

                            Button("Reject") {
                                Task { await reject(item.task) }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Reviews")
        .task { await loadReviews() }
    }

    private func loadReviews() async {
        guard let db = appDatabase else { return }
        do {
            pendingReviews = try await db.dbQueue.read { dbConn in
                let reviews = try Review
                    .filter(Column("verdict") != Review.Verdict.pass.rawValue)
                    .order(Column("createdAt").desc)
                    .fetchAll(dbConn)

                return try reviews.compactMap { review in
                    guard let task = try AgentTask.fetchOne(dbConn, id: review.taskId),
                          let project = try Project.fetchOne(dbConn, id: task.projectId) else {
                        return nil
                    }
                    return (review: review, task: task, project: project)
                }
            }
        } catch {}
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
            await loadReviews()
        } catch {}
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
            await loadReviews()
        } catch {}
    }
}
