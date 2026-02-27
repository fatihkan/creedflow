import SwiftUI
import GRDB

struct ArchivedTasksView: View {
    let appDatabase: AppDatabase?
    @Binding var selectedTaskId: UUID?

    @State private var archivedTasks: [(task: AgentTask, projectName: String)] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showDeleteConfirm = false
    @State private var showRestoreConfirm = false
    @State private var selection: Set<UUID> = []
    @State private var isSelectionMode = false
    @State private var searchText = ""

    private var filteredTasks: [(task: AgentTask, projectName: String)] {
        guard !searchText.isEmpty else { return archivedTasks }
        let query = searchText.lowercased()
        return archivedTasks.filter { item in
            item.task.title.lowercased().contains(query)
            || item.projectName.lowercased().contains(query)
            || item.task.agentType.rawValue.lowercased().contains(query)
            || item.task.status.rawValue.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: "Archive") {
                if !archivedTasks.isEmpty {
                    if isSelectionMode {
                        Button {
                            let visibleIds = Set(filteredTasks.map(\.task.id))
                            if visibleIds.isSubset(of: selection) {
                                selection.subtract(visibleIds)
                            } else {
                                selection.formUnion(visibleIds)
                            }
                        } label: {
                            let visibleIds = Set(filteredTasks.map(\.task.id))
                            Label(
                                visibleIds.isSubset(of: selection) ? "Deselect All" : "Select All",
                                systemImage: visibleIds.isSubset(of: selection) ? "checkmark.circle" : "circle"
                            )
                        }

                        Button {
                            showRestoreConfirm = true
                        } label: {
                            Label("Restore (\(selection.count))", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(selection.isEmpty)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete (\(selection.count))", systemImage: "trash")
                        }
                        .disabled(selection.isEmpty)

                        Button {
                            isSelectionMode = false
                            selection.removeAll()
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                    } else {
                        Button {
                            isSelectionMode = true
                            selection.removeAll()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                        .help("Select tasks to restore or delete")
                    }
                }
            }
            Divider()

            if !archivedTasks.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                    TextField("Search archived tasks...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(.subheadline))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }

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
            } else if filteredTasks.isEmpty {
                ForgeEmptyState(
                    icon: "magnifyingglass",
                    title: "No Results",
                    subtitle: "No archived tasks match \"\(searchText)\""
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredTasks, id: \.task.id) { item in
                            HStack(spacing: 8) {
                                if isSelectionMode {
                                    Button {
                                        toggleSelection(item.task.id)
                                    } label: {
                                        Image(systemName: selection.contains(item.task.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selection.contains(item.task.id) ? .forgeAmber : .secondary)
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.plain)
                                }

                                archivedTaskCard(task: item.task, projectName: item.projectName, isSelected: selectedTaskId == item.task.id)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(.forgeAmber.opacity(0.5), lineWidth: 1.5)
                                            .opacity(isSelectionMode && selection.contains(item.task.id) ? 1 : 0)
                                    )
                            }
                            .onTapGesture {
                                if isSelectionMode {
                                    toggleSelection(item.task.id)
                                } else {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedTaskId = item.task.id
                                    }
                                }
                            }
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
            "Delete Selected Tasks",
            isPresented: $showDeleteConfirm
        ) {
            Button("Delete \(selection.count) Task\(selection.count == 1 ? "" : "s")", role: .destructive) {
                deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected tasks will be permanently deleted along with their logs, reviews, and dependencies. This cannot be undone.")
        }
        .confirmationDialog(
            "Restore Selected Tasks",
            isPresented: $showRestoreConfirm
        ) {
            Button("Restore \(selection.count) Task\(selection.count == 1 ? "" : "s")") {
                restoreSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected tasks will be restored to the Task Board with their original status.")
        }
    }

    // MARK: - Card

    private func archivedTaskCard(task: AgentTask, projectName: String, isSelected: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Agent badge
                HStack(spacing: 3) {
                    Image(systemName: task.agentType.icon)
                    Text(task.agentType.rawValue.capitalized)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(task.agentType.themeColor)

                // Original status badge
                Text(task.status.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                    .forgeBadge(color: statusColor(task.status))

                Spacer()

                if let archivedAt = task.archivedAt {
                    Text("Archived \(archivedAt, style: .relative) ago")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(task.title)
                .font(.system(.subheadline, weight: .semibold))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(projectName)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let duration = task.durationMs {
                    Text(ForgeDuration.format(ms: duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .forgeCard(selected: isSelected, cornerRadius: 8)
        .contextMenu {
            Button {
                restoreTask(task)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Divider()
            Button(role: .destructive) {
                permanentlyDelete(task)
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

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func restoreTask(_ task: AgentTask) {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            try AgentTask
                .filter(Column("id") == task.id)
                .updateAll(dbConn, Column("archivedAt").set(to: nil as Date?), Column("updatedAt").set(to: Date()))
        }
    }

    private func restoreSelected() {
        guard let db = appDatabase, !selection.isEmpty else { return }
        let ids = Array(selection)
        try? db.dbQueue.write { dbConn in
            try AgentTask
                .filter(ids.contains(Column("id")))
                .updateAll(dbConn, Column("archivedAt").set(to: nil as Date?), Column("updatedAt").set(to: Date()))
        }
        selection.removeAll()
        isSelectionMode = false
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

    private func deleteSelected() {
        guard let db = appDatabase, !selection.isEmpty else { return }
        let ids = Array(selection)
        try? db.dbQueue.write { dbConn in
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
        selection.removeAll()
        isSelectionMode = false
    }
}
