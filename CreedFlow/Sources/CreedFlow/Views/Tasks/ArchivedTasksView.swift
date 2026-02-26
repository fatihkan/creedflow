import SwiftUI
import GRDB

struct ArchivedTasksView: View {
    let appDatabase: AppDatabase?

    @State private var archivedTasks: [(task: AgentTask, projectName: String)] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showDeleteAllConfirm = false
    @State private var taskToDelete: AgentTask?

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Archive") {
                if !archivedTasks.isEmpty {
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                    .help("Permanently delete all archived tasks")
                }
            }
            Divider()

            if let errorMessage {
                ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            if isLoading && archivedTasks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if archivedTasks.isEmpty {
                ForgeEmptyState(
                    icon: "archivebox",
                    title: "Archive Empty",
                    subtitle: "Archived tasks will appear here. Use \"Archive\" on the Task Board to move completed, failed, or cancelled tasks here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(archivedTasks, id: \.task.id) { item in
                            archivedTaskCard(task: item.task, projectName: item.projectName)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task {
            await observeArchivedTasks()
        }
        .confirmationDialog(
            "Delete All Archived Tasks",
            isPresented: $showDeleteAllConfirm
        ) {
            Button("Delete All (\(archivedTasks.count))", role: .destructive) {
                deleteAllArchived()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived tasks will be permanently deleted along with their logs, reviews, and dependencies. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete Task",
            isPresented: Binding(
                get: { taskToDelete != nil },
                set: { if !$0 { taskToDelete = nil } }
            ),
            presenting: taskToDelete
        ) { task in
            Button("Delete \"\(task.title)\"", role: .destructive) {
                permanentlyDelete(task)
            }
        } message: { _ in
            Text("This task will be permanently deleted along with its logs, reviews, and dependencies. This cannot be undone.")
        }
    }

    // MARK: - Card

    private func archivedTaskCard(task: AgentTask, projectName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Agent badge
                HStack(spacing: 3) {
                    Image(systemName: task.agentType.icon)
                    Text(task.agentType.rawValue.capitalized)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(task.agentType.themeColor)

                // Original status badge
                Text(task.status.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                    .forgeBadge(color: statusColor(task.status))

                Spacer()

                if let archivedAt = task.archivedAt {
                    Text("Archived \(archivedAt, style: .relative) ago")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(task.title)
                .font(.system(.subheadline, weight: .semibold))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(projectName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let duration = task.durationMs {
                    Text(ForgeDuration.format(ms: duration))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .forgeCard(cornerRadius: 8)
        .contextMenu {
            Button {
                restoreTask(task)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Divider()
            Button(role: .destructive) {
                taskToDelete = task
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
        }
    }

    private func statusColor(_ status: AgentTask.Status) -> Color {
        switch status {
        case .passed: return .forgeSuccess
        case .failed: return .forgeDanger
        case .cancelled: return .forgeNeutral
        case .queued: return .forgeNeutral
        case .inProgress: return .forgeInfo
        case .needsRevision: return .forgeWarning
        }
    }

    // MARK: - Observation

    private func observeArchivedTasks() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            let tasks = try AgentTask
                .filter(Column("archivedAt") != nil)
                .order(Column("archivedAt").desc)
                .fetchAll(db)

            return try tasks.map { task -> (task: AgentTask, projectName: String) in
                let name = try Project.fetchOne(db, id: task.projectId)?.name ?? "Unknown"
                return (task: task, projectName: name)
            }
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                archivedTasks = value
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func restoreTask(_ task: AgentTask) {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            try AgentTask
                .filter(Column("id") == task.id)
                .updateAll(dbConn, Column("archivedAt").set(to: nil as Date?), Column("updatedAt").set(to: Date()))
        }
    }

    private func permanentlyDelete(_ task: AgentTask) {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            try TaskDependency
                .filter(Column("taskId") == task.id || Column("dependsOnTaskId") == task.id)
                .deleteAll(dbConn)
            try AgentLog
                .filter(Column("taskId") == task.id)
                .deleteAll(dbConn)
            try Review
                .filter(Column("taskId") == task.id)
                .deleteAll(dbConn)
            try AgentTask
                .filter(Column("id") == task.id)
                .deleteAll(dbConn)
        }
    }

    private func deleteAllArchived() {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            let ids = try AgentTask
                .filter(Column("archivedAt") != nil)
                .select(Column("id"))
                .fetchAll(dbConn)
                .map(\.id)
            guard !ids.isEmpty else { return }
            try TaskDependency
                .filter(ids.contains(Column("taskId")) || ids.contains(Column("dependsOnTaskId")))
                .deleteAll(dbConn)
            try AgentLog
                .filter(ids.contains(Column("taskId")))
                .deleteAll(dbConn)
            try Review
                .filter(ids.contains(Column("taskId")))
                .deleteAll(dbConn)
            try AgentTask
                .filter(ids.contains(Column("id")))
                .deleteAll(dbConn)
        }
    }
}
