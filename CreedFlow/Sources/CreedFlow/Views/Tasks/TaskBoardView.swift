import SwiftUI
import GRDB
import UniformTypeIdentifiers

/// Kanban-style board showing tasks grouped by status with real-time updates.
struct TaskBoardView: View {
    let projectId: UUID?
    @Binding var selectedTaskId: UUID?
    let appDatabase: AppDatabase?
    let orchestrator: Orchestrator?
    var onNavigateToSettings: (() -> Void)?
    @Binding var showChatPanel: Bool
    var onChatProjectChanged: ((UUID?) -> Void)?

    @State private var filterProjectId: UUID?
    @State private var projects: [Project] = []
    @State private var tasks: [AgentTask] = []
    @State private var projectName: String = ""
    @State private var errorMessage: String?
    @State private var showNewTask = false
    @State private var showArchiveConfirm = false
    @State private var archiveSelection: Set<UUID> = []
    @State private var isArchiveSelectionMode = false
    @State private var searchText: String = ""

    init(projectId: UUID?, selectedTaskId: Binding<UUID?>, appDatabase: AppDatabase?, orchestrator: Orchestrator?, onNavigateToSettings: (() -> Void)? = nil, showChatPanel: Binding<Bool> = .constant(false), onChatProjectChanged: ((UUID?) -> Void)? = nil) {
        self.projectId = projectId
        self._selectedTaskId = selectedTaskId
        self.appDatabase = appDatabase
        self.orchestrator = orchestrator
        self.onNavigateToSettings = onNavigateToSettings
        self._showChatPanel = showChatPanel
        self.onChatProjectChanged = onChatProjectChanged
        self._filterProjectId = State(initialValue: projectId)
    }

    private let columns: [KanbanColumn] = [
        KanbanColumn(title: "Queued", status: .queued, color: .forgeNeutral),
        KanbanColumn(title: "In Progress", status: .inProgress, color: .forgeInfo),
        KanbanColumn(title: "Review", status: .needsRevision, color: .forgeWarning),
        KanbanColumn(title: "Done", status: .passed, color: .forgeSuccess),
        KanbanColumn(title: "Failed", status: .failed, color: .forgeDanger),
        KanbanColumn(title: "Cancelled", status: .cancelled, color: .forgeNeutral),
    ]

    /// Tasks that can be archived (done + failed + cancelled)
    private var archivableTasks: [AgentTask] {
        tasks.filter { $0.status == .passed || $0.status == .failed || $0.status == .cancelled }
    }

    private var archivableCount: Int { archivableTasks.count }

    /// Tasks that can be retried (failed + needs_revision + cancelled)
    private static let retryableStatuses: Set<AgentTask.Status> = [.failed, .needsRevision, .cancelled]

    /// Selected tasks eligible for each batch action
    private var selectedRetryableCount: Int {
        tasks.filter { archiveSelection.contains($0.id) && Self.retryableStatuses.contains($0.status) }.count
    }
    private var selectedCancellableCount: Int {
        tasks.filter { archiveSelection.contains($0.id) && $0.status == .queued }.count
    }
    private var selectedArchivableCount: Int {
        tasks.filter { archiveSelection.contains($0.id) && ($0.status == .passed || $0.status == .failed || $0.status == .cancelled) }.count
    }

    /// Count of failed tasks whose error message mentions MCP
    private var mcpFailedCount: Int {
        tasks.filter { task in
            task.status == .failed &&
            (task.errorMessage?.localizedCaseInsensitiveContains("MCP") == true ||
             task.errorMessage?.localizedCaseInsensitiveContains("creative AI service") == true)
        }.count
    }

    /// Tasks filtered by search text (matches title, description, agent type, backend)
    private var filteredTasks: [AgentTask] {
        guard !searchText.isEmpty else { return tasks }
        let query = searchText.lowercased()
        return tasks.filter { task in
            task.title.lowercased().contains(query)
            || task.description.lowercased().contains(query)
            || task.agentType.rawValue.lowercased().contains(query)
            || (task.backend?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: projectName.isEmpty ? "Task Board" : "Tasks — \(projectName)") {
                HStack(spacing: 8) {
                    if filterProjectId != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showChatPanel.toggle()
                                if showChatPanel {
                                    onChatProjectChanged?(filterProjectId)
                                }
                            }
                        } label: {
                            Image(systemName: showChatPanel ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                .font(.system(size: 14))
                                .foregroundStyle(showChatPanel ? .forgeAmber : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(showChatPanel ? "Close AI Chat" : "Open AI Chat")
                        .accessibilityLabel(showChatPanel ? "Close AI Chat" : "Open AI Chat")
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        TextField("Search tasks...", text: $searchText)
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
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .frame(width: 180)

                    Picker("Project", selection: $filterProjectId) {
                        Text("All").tag(UUID?.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(UUID?.some(project.id))
                        }
                    }
                    .frame(maxWidth: 200)

                    if isArchiveSelectionMode {
                        if !archiveSelection.isEmpty {
                            Text("\(archiveSelection.count) selected")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        if selectedRetryableCount > 0 {
                            Button {
                                batchRetryTasks()
                            } label: {
                                Label("Re-queue (\(selectedRetryableCount))", systemImage: "arrow.counterclockwise")
                            }
                            .help("Re-queue failed/revision/cancelled tasks")
                        }

                        if selectedCancellableCount > 0 {
                            Button {
                                batchCancelTasks()
                            } label: {
                                Label("Cancel (\(selectedCancellableCount))", systemImage: "xmark.circle")
                            }
                            .help("Cancel queued tasks")
                        }

                        if selectedArchivableCount > 0 {
                            Button {
                                showArchiveConfirm = true
                            } label: {
                                Label("Archive (\(selectedArchivableCount))", systemImage: "archivebox")
                            }
                        }

                        Button {
                            isArchiveSelectionMode = false
                            archiveSelection.removeAll()
                        } label: {
                            Label("Done", systemImage: "xmark")
                        }
                    } else {
                        Button {
                            isArchiveSelectionMode = true
                            archiveSelection.removeAll()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                        .help("Select tasks for batch operations")
                    }

                    if filterProjectId != nil {
                        Button {
                            showNewTask = true
                        } label: {
                            Label("New Task", systemImage: "plus")
                        }
                    }
                }
            }
            Divider()

            if let errorMessage {
                ForgeErrorBanner(message: errorMessage, onDismiss: { self.errorMessage = nil })
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // MCP warning banner for tasks that failed due to missing MCP configuration
            if mcpFailedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.forgeWarning)
                    Text("\(mcpFailedCount) task(s) failed: Missing MCP server configuration.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let onNavigateToSettings {
                        Button("Go to Settings") {
                            onNavigateToSettings()
                        }
                        .font(.footnote.weight(.medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color.forgeWarning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.forgeWarning.opacity(0.2), lineWidth: 0.5)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns, id: \.title) { column in
                        KanbanColumnView(
                            column: column,
                            tasks: filteredTasks.filter { $0.status == column.status },
                            selectedTaskId: $selectedTaskId,
                            orchestrator: orchestrator,
                            isArchiveSelectionMode: isArchiveSelectionMode,
                            archiveSelection: $archiveSelection,
                            onMoveTask: { taskId, newStatus in
                                moveTask(taskId: taskId, to: newStatus)
                            },
                            onDuplicateTask: { taskId in
                                duplicateTask(taskId: taskId)
                            }
                        )
                    }
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showNewTask) {
            if let pid = filterProjectId {
                NewTaskSheet(projectId: pid, appDatabase: appDatabase)
            }
        }
        .confirmationDialog(
            "Archive Tasks",
            isPresented: $showArchiveConfirm
        ) {
            Button("Archive \(archiveSelection.count) Selected Task\(archiveSelection.count == 1 ? "" : "s")") {
                archiveTasks()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected tasks will be moved to the archive. You can restore or permanently delete them later.")
        }
        .onChange(of: projectId) { _, newValue in
            filterProjectId = newValue
            isArchiveSelectionMode = false
            archiveSelection.removeAll()
        }
        .onChange(of: filterProjectId) { _, newValue in
            if newValue == nil {
                showChatPanel = false
            } else if showChatPanel {
                onChatProjectChanged?(newValue)
            }
        }
        .task(id: filterProjectId) {
            await observeTasks()
        }
        .task {
            await observeProjects()
        }
    }

    private func observeProjects() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try Project.order(Column("name")).fetchAll(db)
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                projects = value
            }
        } catch {
            // Picker will just show no projects
        }
    }

    private func observeTasks() async {
        guard let db = appDatabase else { return }
        // Fetch project name for title
        if let pid = filterProjectId,
           let project = try? await db.dbQueue.read({ db in try Project.fetchOne(db, id: pid) }) {
            projectName = project.name
        } else {
            projectName = ""
        }
        let pid = filterProjectId
        let observation = ValueObservation.tracking { db in
            var query = AgentTask
                .filter(Column("archivedAt") == nil)
                .order(Column("priority").desc, Column("createdAt").asc)
            if let pid {
                query = query.filter(Column("projectId") == pid)
            }
            return try query.fetchAll(db)
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                tasks = value
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archiveTasks() {
        guard let db = appDatabase, !archiveSelection.isEmpty else { return }
        let idsToArchive = Array(archiveSelection)
        let now = Date()
        try? db.dbQueue.write { dbConn in
            try AgentTask
                .filter(idsToArchive.contains(Column("id")))
                .updateAll(dbConn, Column("archivedAt").set(to: now), Column("updatedAt").set(to: now))
        }
        if let selected = selectedTaskId, archiveSelection.contains(selected) {
            selectedTaskId = nil
        }
        archiveSelection.removeAll()
        isArchiveSelectionMode = false
    }

    private func batchRetryTasks() {
        guard let db = appDatabase else { return }
        let retryableIds = tasks
            .filter { archiveSelection.contains($0.id) && Self.retryableStatuses.contains($0.status) }
            .map(\.id)
        guard !retryableIds.isEmpty else { return }
        try? db.dbQueue.write { dbConn in
            try AgentTask
                .filter(retryableIds.contains(Column("id")))
                .updateAll(
                    dbConn,
                    Column("status").set(to: AgentTask.Status.queued.rawValue),
                    Column("retryCount").set(to: Column("retryCount") + 1),
                    Column("updatedAt").set(to: Date())
                )
        }
        archiveSelection.removeAll()
        isArchiveSelectionMode = false
    }

    private func batchCancelTasks() {
        guard let db = appDatabase else { return }
        let cancellableIds = tasks
            .filter { archiveSelection.contains($0.id) && $0.status == .queued }
            .map(\.id)
        guard !cancellableIds.isEmpty else { return }
        try? db.dbQueue.write { dbConn in
            try AgentTask
                .filter(cancellableIds.contains(Column("id")))
                .updateAll(
                    dbConn,
                    Column("status").set(to: AgentTask.Status.cancelled.rawValue),
                    Column("updatedAt").set(to: Date())
                )
        }
        archiveSelection.removeAll()
        isArchiveSelectionMode = false
    }

    private func moveTask(taskId: UUID, to newStatus: AgentTask.Status) {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            guard var task = try AgentTask.fetchOne(dbConn, id: taskId) else { return }
            task.status = newStatus
            task.updatedAt = Date()
            if newStatus == .inProgress && task.startedAt == nil {
                task.startedAt = Date()
            }
            if newStatus == .passed || newStatus == .failed || newStatus == .cancelled {
                task.completedAt = Date()
            }
            if newStatus == .queued {
                task.errorMessage = nil
            }
            try task.update(dbConn)
        }
    }

    private func duplicateTask(taskId: UUID) {
        guard let db = appDatabase else { return }
        do {
            try db.dbQueue.write { dbConn in
                guard let source = try AgentTask.fetchOne(dbConn, id: taskId) else { return }
                var copy = AgentTask(
                    projectId: source.projectId,
                    featureId: source.featureId,
                    agentType: source.agentType,
                    title: "Copy of \(source.title)",
                    description: source.description,
                    priority: source.priority,
                    maxRetries: source.maxRetries,
                    promptChainId: source.promptChainId,
                    skillPersona: source.skillPersona
                )
                try copy.insert(dbConn)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - New Task Sheet

private struct NewTaskSheet: View {
    let projectId: UUID
    let appDatabase: AppDatabase?
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var agentType: AgentTask.AgentType = .coder
    @State private var priority: Int = 5

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Task Info") {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                    ZStack(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Describe the task...")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $description)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                    }
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                }
                Section("Configuration") {
                    Picker("Agent Type", selection: $agentType) {
                        ForEach(AgentTask.AgentType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    Stepper("Priority: \(priority)", value: $priority, in: 1...10)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { createTask() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 340)
    }

    private func createTask() {
        guard let db = appDatabase else { return }
        try? db.dbQueue.write { dbConn in
            var task = AgentTask(
                projectId: projectId,
                agentType: agentType,
                title: title,
                description: description,
                priority: priority
            )
            try task.insert(dbConn)
        }
        dismiss()
    }
}

struct KanbanColumn {
    let title: String
    let status: AgentTask.Status
    let color: Color
}

struct KanbanColumnView: View {
    let column: KanbanColumn
    let tasks: [AgentTask]
    @Binding var selectedTaskId: UUID?
    let orchestrator: Orchestrator?
    var isArchiveSelectionMode: Bool = false
    @Binding var archiveSelection: Set<UUID>
    let onMoveTask: (UUID, AgentTask.Status) -> Void
    var onDuplicateTask: ((UUID) -> Void)?

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Column header
            HStack(spacing: 6) {
                Circle()
                    .fill(column.color)
                    .frame(width: 8, height: 8)
                Text(column.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            .padding(.bottom, 4)
            .help("\(column.title) — \(tasks.count) task(s)")

            // Task cards
            if tasks.isEmpty {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDropTargeted ? AnyShapeStyle(column.color.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.15)))
                    .frame(height: 32)
                    .overlay {
                        Text(isDropTargeted ? "Drop here" : "Empty")
                            .font(.system(size: 12))
                            .foregroundStyle(isDropTargeted ? AnyShapeStyle(column.color) : AnyShapeStyle(.quaternary))
                    }
                    .animation(.easeOut(duration: 0.15), value: isDropTargeted)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(tasks) { task in
                            HStack(spacing: 6) {
                                if isArchiveSelectionMode {
                                    Button {
                                        if archiveSelection.contains(task.id) {
                                            archiveSelection.remove(task.id)
                                        } else {
                                            archiveSelection.insert(task.id)
                                        }
                                    } label: {
                                        Image(systemName: archiveSelection.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(archiveSelection.contains(task.id) ? .forgeAmber : .secondary)
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(archiveSelection.contains(task.id) ? "Deselect task for archive" : "Select task for archive")
                                }

                                TaskCardView(
                                    task: task,
                                    isSelected: selectedTaskId == task.id,
                                    isRunning: orchestrator?.runner(for: task.id) != nil,
                                    onMoveTask: onMoveTask,
                                    onDuplicateTask: onDuplicateTask
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(.forgeAmber.opacity(0.5), lineWidth: 1.5)
                                        .opacity(isArchiveSelectionMode && archiveSelection.contains(task.id) ? 1 : 0)
                                )
                            }
                            .onTapGesture {
                                if isArchiveSelectionMode {
                                    if archiveSelection.contains(task.id) {
                                        archiveSelection.remove(task.id)
                                    } else {
                                        archiveSelection.insert(task.id)
                                    }
                                } else {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedTaskId = task.id
                                    }
                                }
                            }
                            .draggable(task.id.uuidString)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 280, maxHeight: .infinity)
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first, let taskId = UUID(uuidString: idString) else { return false }
            onMoveTask(taskId, column.status)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }
}

struct TaskCardView: View {
    let task: AgentTask
    let isSelected: Bool
    var isRunning: Bool = false
    let onMoveTask: (UUID, AgentTask.Status) -> Void
    var onDuplicateTask: ((UUID) -> Void)?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                // Agent badge
                HStack(spacing: 3) {
                    Image(systemName: task.agentType.icon)
                    Text(task.agentType.rawValue.capitalized)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(task.agentType.themeColor)

                // Backend badge
                if let backend = task.backend {
                    Text(backend.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(backendColor(backend))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(backendColor(backend).opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                if isRunning {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                }
            }

            Text(task.title)
                .font(.system(.footnote, weight: .semibold))
                .lineLimit(2)

            Text(task.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                if task.priority > 0 {
                    Text("P\(task.priority)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.forgeAmber)
                        .help("Priority \(task.priority) (1=low, 10=critical)")
                }
                Spacer()
                if task.status == .inProgress, let startedAt = task.startedAt {
                    LiveTimerView(since: startedAt)
                } else if let duration = task.durationMs {
                    Text(ForgeDuration.format(ms: duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .forgeCard(selected: isSelected, hovered: isHovered, cornerRadius: 8)
        .onHover { isHovered = $0 }
        .contextMenu { taskContextMenu }
    }

    private func backendColor(_ backend: String) -> Color {
        switch backend.lowercased() {
        case "claude": return .purple
        case "codex": return .green
        case "gemini": return .blue
        case "opencode": return .teal
        case "ollama": return .orange
        case "lmstudio": return .cyan
        case "llamacpp": return .pink
        case "mlx": return .mint
        default: return .secondary
        }
    }

    @ViewBuilder
    private var taskContextMenu: some View {
        // Status transitions
        switch task.status {
        case .queued:
            Button { onMoveTask(task.id, .inProgress) } label: {
                Label("Start", systemImage: "play.fill")
            }
            Button { onMoveTask(task.id, .cancelled) } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }

        case .inProgress:
            Button { onMoveTask(task.id, .queued) } label: {
                Label("Pause (Back to Queue)", systemImage: "pause.fill")
            }
            Button { onMoveTask(task.id, .passed) } label: {
                Label("Mark as Done", systemImage: "checkmark.circle.fill")
            }
            Button { onMoveTask(task.id, .needsRevision) } label: {
                Label("Send to Review", systemImage: "eye.fill")
            }
            Divider()
            Button(role: .destructive) { onMoveTask(task.id, .cancelled) } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }

        case .needsRevision:
            Button { onMoveTask(task.id, .inProgress) } label: {
                Label("Resume Work", systemImage: "play.fill")
            }
            Button { onMoveTask(task.id, .passed) } label: {
                Label("Approve", systemImage: "checkmark.circle.fill")
            }
            Button(role: .destructive) { onMoveTask(task.id, .failed) } label: {
                Label("Reject", systemImage: "xmark.circle")
            }

        case .passed:
            Button { onMoveTask(task.id, .inProgress) } label: {
                Label("Reopen", systemImage: "arrow.counterclockwise")
            }

        case .failed:
            Button { onMoveTask(task.id, .queued) } label: {
                Label("Retry", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) { onMoveTask(task.id, .cancelled) } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }

        case .cancelled:
            Button { onMoveTask(task.id, .queued) } label: {
                Label("Requeue", systemImage: "arrow.counterclockwise")
            }
        }

        Divider()

        Button { onDuplicateTask?(task.id) } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }
    }
}

