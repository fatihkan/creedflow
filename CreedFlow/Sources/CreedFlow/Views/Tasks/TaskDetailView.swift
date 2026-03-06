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
    @State private var revisionText: String = ""
    @State private var comments: [TaskComment] = []
    @State private var newCommentText: String = ""
    @State private var promptHistory: [PromptUsageWithTitle] = []
    @Environment(\.undoManager) private var undoManager

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
                            .font(.system(size: 12, weight: .bold, design: .rounded))
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
                        .accessibilityLabel("Close detail panel")
                        .help("Close (Esc)")
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
                        if let duration = task.durationMs {
                            metadataItem(label: "Duration", value: ForgeDuration.format(ms: duration), icon: "clock")
                        }
                        if let backend = task.backend {
                            metadataItem(label: "Backend", value: backend.capitalized, icon: "cpu")
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
                                        .font(.caption)
                                    Text("Showing last 200 entries. Older logs may be truncated.")
                                        .font(.caption)
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
                                .font(.system(.footnote, design: .monospaced))
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
                            ForEach(reviews, id: \.id) { review in
                                ReviewRowView(review: review)
                            }
                        }
                    }

                    commentsSection

                    promptHistorySection

                    // Revision prompt (for failed/needs_revision tasks)
                    if task.status == .failed || task.status == .needsRevision {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Revision Instructions (optional)")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            TextEditor(text: $revisionText)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(minHeight: 60, maxHeight: 120)
                                .padding(4)
                                .background(.quaternary.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.quaternary, lineWidth: 1)
                                )
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
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Comments Section

    @ViewBuilder
    private var commentsSection: some View {
        DisclosureGroup("Comments (\(comments.count))") {
            VStack(alignment: .leading, spacing: 6) {
                if comments.isEmpty {
                    Text("No comments yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(comments, id: \.id) { comment in
                        commentRow(comment)
                    }
                }

                HStack(spacing: 6) {
                    TextField("Add a comment...", text: $newCommentText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    Button {
                        Task { await addComment() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.forgeAmber)
                    .controlSize(.small)
                    .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.top, 4)
        }
        .font(.subheadline.bold())
    }

    private func commentRow(_ comment: TaskComment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: comment.author == .user ? "person.circle.fill" : "gearshape.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(comment.author == .user ? .forgeInfo : .forgeNeutral)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(comment.author == .user ? "You" : "System")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(comment.createdAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Text(comment.content)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(6)
        .background(comment.author == .user ? Color.forgeInfo.opacity(0.05) : Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Prompt History Section

    @ViewBuilder
    private var promptHistorySection: some View {
        if !promptHistory.isEmpty {
            DisclosureGroup("Prompt History (\(promptHistory.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(promptHistory, id: \.id) { record in
                        promptHistoryRow(record)
                    }
                }
                .padding(.top, 4)
            }
            .font(.subheadline.bold())
        }
    }

    private func promptHistoryRow(_ record: PromptUsageWithTitle) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundStyle(.forgeNeutral)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(record.promptTitle ?? "Untitled prompt")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if let outcome = record.outcome {
                        HStack(spacing: 2) {
                            Image(systemName: outcome == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 10))
                            Text(outcome.rawValue)
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(outcome == .completed ? .forgeSuccess : .forgeDanger)
                    }
                }
                HStack(spacing: 6) {
                    if let agent = record.agentType {
                        Text(agent)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    if let score = record.reviewScore {
                        Text(String(format: "%.1f/10", score))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(score >= 7.0 ? .forgeSuccess : score >= 5.0 ? .forgeWarning : .forgeDanger)
                    }
                    Spacer()
                    Text(record.usedAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(6)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Data Observation

    private func observeData() async {
        guard let db = appDatabase else { return }
        let tid = taskId
        let observation = ValueObservation.tracking { db -> (AgentTask?, [Review], [AgentLog], [TaskComment], [PromptUsageWithTitle]) in
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
            let comments = try TaskComment
                .filter(Column("taskId") == tid)
                .order(Column("createdAt").asc)
                .fetchAll(db)
            let prompts = try PromptUsageWithTitle.fetchAll(db, sql: """
                SELECT pu.id, pu.promptId, pu.agentType, pu.outcome, pu.reviewScore, pu.usedAt,
                       p.title AS promptTitle
                FROM promptUsage pu
                LEFT JOIN prompt p ON p.id = pu.promptId
                WHERE pu.taskId = ?
                ORDER BY pu.usedAt DESC
                """, arguments: [tid.uuidString])
            return (task, reviews, logs, comments, prompts)
        }
        do {
            for try await (t, r, l, c, p) in observation.values(in: db.dbQueue) {
                task = t
                reviews = r
                logs = l
                comments = c
                promptHistory = p
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addComment() async {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let db = appDatabase else { return }
        do {
            try await db.dbQueue.write { dbConn in
                let comment = TaskComment(taskId: taskId, content: text, author: .user)
                try comment.save(dbConn)
            }
            newCommentText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func retryTask() async {
        guard let db = appDatabase else { return }
        let revision = revisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousStatus = task?.status
        do {
            try await db.dbQueue.write { dbConn in
                guard var t = try AgentTask.fetchOne(dbConn, id: taskId) else { return }
                // Only allow retry from terminal/revisable states
                guard [.failed, .needsRevision, .cancelled].contains(t.status) else {
                    throw NSError(domain: "CreedFlow", code: 0,
                                  userInfo: [NSLocalizedDescriptionKey: "Only failed, needs_revision, or cancelled tasks can be retried"])
                }
                t.status = .queued
                t.retryCount += 1
                t.errorMessage = nil
                if !revision.isEmpty {
                    t.revisionPrompt = revision
                }
                t.updatedAt = Date()
                try t.update(dbConn)
            }
            revisionText = ""
            registerStatusUndo(from: .queued, to: previousStatus, actionName: "Retry Task")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelTask() async {
        guard let db = appDatabase else { return }
        let previousStatus = task?.status
        do {
            try await db.dbQueue.write { dbConn in
                guard var t = try AgentTask.fetchOne(dbConn, id: taskId) else { return }
                t.status = .cancelled
                t.updatedAt = Date()
                t.completedAt = Date()
                try t.update(dbConn)
            }
            registerStatusUndo(from: .cancelled, to: previousStatus, actionName: "Cancel Task")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func registerStatusUndo(from newStatus: AgentTask.Status, to previousStatus: AgentTask.Status?, actionName: String) {
        guard let undoManager, let previousStatus, let db = appDatabase else { return }
        let tid = taskId
        undoManager.registerUndo(withTarget: UndoTarget.shared) { _ in
            Task {
                try? await db.dbQueue.write { dbConn in
                    guard var t = try AgentTask.fetchOne(dbConn, id: tid) else { return }
                    t.status = previousStatus
                    t.updatedAt = Date()
                    try t.update(dbConn)
                }
            }
        }
        undoManager.setActionName(actionName)
    }
}

// MARK: - Review Row

struct ReviewRowView: View {
    let review: Review

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(review.verdict.rawValue.uppercased())
                    .forgeBadge(color: verdictColor)

                Text(String(format: "%.1f/10", review.score))
                    .font(.system(.footnote, design: .monospaced, weight: .medium))

                Text(review.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 1)

                Spacer()

                Text(review.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !review.summary.isEmpty {
                        Text(review.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let issues = review.issues, !issues.isEmpty {
                        reviewDetailSection(title: "Issues", text: issues, color: .forgeDanger)
                    }
                    if let suggestions = review.suggestions, !suggestions.isEmpty {
                        reviewDetailSection(title: "Suggestions", text: suggestions, color: .forgeInfo)
                    }
                    if let securityNotes = review.securityNotes, !securityNotes.isEmpty {
                        reviewDetailSection(title: "Security", text: securityNotes, color: .forgeWarning)
                    }
                }
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 3)
    }

    private func reviewDetailSection(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
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
                ForEach(logs, id: \.id) { log in
                    HStack(alignment: .top, spacing: 6) {
                        Text(log.createdAt, format: .dateTime.hour().minute().second())
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.forgeNeutral)
                            .frame(width: 60, alignment: .leading)

                        Text(log.level.rawValue.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(logColor(for: log.level))
                            .frame(width: 36, alignment: .leading)

                        Text(log.message)
                            .font(.system(size: 13, design: .monospaced))
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

// MARK: - Prompt Usage With Title (join result)

struct PromptUsageWithTitle: Codable, FetchableRecord {
    var id: UUID
    var promptId: UUID
    var agentType: String?
    var outcome: PromptUsage.Outcome?
    var reviewScore: Double?
    var usedAt: Date
    var promptTitle: String?
}

// MARK: - Undo Helper

/// Singleton target for `UndoManager.registerUndo(withTarget:)` — the undo closure captures all needed state.
private final class UndoTarget: NSObject {
    static let shared = UndoTarget()
}
