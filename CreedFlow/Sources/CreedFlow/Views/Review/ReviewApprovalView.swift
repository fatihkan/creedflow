import SwiftUI
import GRDB

struct ReviewApprovalView: View {
    let appDatabase: AppDatabase?
    @State private var pendingReviews: [(review: Review, task: AgentTask, project: Project)] = []
    @State private var errorMessage: String?
    @State private var taskToReject: AgentTask?
    @State private var isLoading = true
    @State private var searchText = ""

    private var filteredReviews: [(review: Review, task: AgentTask, project: Project)] {
        guard !searchText.isEmpty else { return pendingReviews }
        let query = searchText.lowercased()
        return pendingReviews.filter { item in
            item.review.summary.lowercased().contains(query)
            || item.review.verdict.rawValue.lowercased().contains(query)
            || item.task.title.lowercased().contains(query)
            || item.project.name.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Reviews") {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    TextField("Search reviews...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .frame(width: 180)
            }
            Divider()

            if isLoading && pendingReviews.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredReviews.isEmpty && !searchText.isEmpty {
                ForgeEmptyState(
                    icon: "magnifyingglass",
                    title: "No Results",
                    subtitle: "No reviews match \"\(searchText)\""
                )
            } else if filteredReviews.isEmpty && errorMessage == nil {
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

                        ForEach(filteredReviews, id: \.review.id) { item in
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
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Text("Score: \(String(format: "%.1f", item.review.score))/10")
                    .font(.system(.footnote, design: .monospaced, weight: .medium))
            }

            Text(item.review.summary)
                .font(.footnote)
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
                .filter(Column("isApproved") == false)
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
                // Mark the review as approved
                let reviews = try Review
                    .filter(Column("taskId") == task.id)
                    .fetchAll(dbConn)
                for var review in reviews {
                    review.isApproved = true
                    try review.update(dbConn)
                }

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
                // Mark the review as approved (processed)
                let reviews = try Review
                    .filter(Column("taskId") == task.id)
                    .fetchAll(dbConn)
                for var review in reviews {
                    review.isApproved = true
                    try review.update(dbConn)
                }

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
