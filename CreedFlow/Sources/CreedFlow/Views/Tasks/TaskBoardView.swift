import SwiftUI
import GRDB
import UniformTypeIdentifiers

/// Kanban-style board showing tasks grouped by status with real-time updates.
struct TaskBoardView: View {
    let projectId: UUID?
    @Binding var selectedTaskId: UUID?
    let appDatabase: AppDatabase?
    let orchestrator: Orchestrator?

    @State private var filterProjectId: UUID?
    @State private var projects: [Project] = []
    @State private var tasks: [AgentTask] = []
    @State private var projectName: String = ""
    @State private var errorMessage: String?
    @State private var showNewTask = false
    @State private var showCleanupConfirm = false

    init(projectId: UUID?, selectedTaskId: Binding<UUID?>, appDatabase: AppDatabase?, orchestrator: Orchestrator?) {
        self.projectId = projectId
        self._selectedTaskId = selectedTaskId
        self.appDatabase = appDatabase
        self.orchestrator = orchestrator
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

    /// Count of tasks that can be cleaned up (done + failed + cancelled)
    private var cleanableCount: Int {
        tasks.filter { $0.status == .passed || $0.status == .failed || $0.status == .cancelled }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeToolbar(title: projectName.isEmpty ? "Task Board" : "Tasks — \(projectName)") {
                HStack(spacing: 8) {
                    Picker("Project", selection: $filterProjectId) {
                        Text("All").tag(UUID?.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(UUID?.some(project.id))
                        }
                    }
                    .frame(maxWidth: 200)

                    if cleanableCount > 0 {
                        Button {
                            showCleanupConfirm = true
                        } label: {
                            Label("Clean Up", systemImage: "trash")
                        }
                        .help("Remove \(cleanableCount) completed, failed, and cancelled tasks")
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns, id: \.title) { column in
                        KanbanColumnView(
                            column: column,
                            tasks: tasks.filter { $0.status == column.status },
                            selectedTaskId: $selectedTaskId,
                            orchestrator: orchestrator,
                            onMoveTask: { taskId, newStatus in
                                moveTask(taskId: taskId, to: newStatus)
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
            "Clean Up Tasks",
            isPresented: $showCleanupConfirm
        ) {
            Button("Remove Done, Failed & Cancelled (\(cleanableCount))", role: .destructive) {
                cleanUpTasks()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all completed, failed, and cancelled tasks. Active and queued tasks will not be affected.")
        }
        .onChange(of: projectId) { _, newValue in
            filterProjectId = newValue
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
            var query = AgentTask.order(Column("priority").desc, Column("createdAt").asc)
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

    private func cleanUpTasks() {
        guard let db = appDatabase else { return }
        let terminalStatuses: [AgentTask.Status] = [.passed, .failed, .cancelled]
        try? db.dbQueue.write { dbConn in
            let idsToDelete = tasks
                .filter { terminalStatuses.contains($0.status) }
                .map(\.id)
            guard !idsToDelete.isEmpty else { return }
            // Delete dependencies referencing these tasks
            try TaskDependency
                .filter(idsToDelete.contains(Column("taskId")) || idsToDelete.contains(Column("dependsOnTaskId")))
                .deleteAll(dbConn)
            // Delete agent logs for these tasks
            try AgentLog
                .filter(idsToDelete.contains(Column("taskId")))
                .deleteAll(dbConn)
            // Delete reviews for these tasks
            try Review
                .filter(idsToDelete.contains(Column("taskId")))
                .deleteAll(dbConn)
            // Delete the tasks themselves
            try AgentTask
                .filter(idsToDelete.contains(Column("id")))
                .deleteAll(dbConn)
        }
        // Clear selection if the selected task was cleaned up
        if let selected = selectedTaskId,
           !tasks.contains(where: { $0.id == selected && ($0.status == .queued || $0.status == .inProgress || $0.status == .needsRevision) }) {
            selectedTaskId = nil
        }
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
    let onMoveTask: (UUID, AgentTask.Status) -> Void

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
                    .font(.system(size: 10, weight: .medium, design: .rounded))
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
                            .font(.system(size: 10))
                            .foregroundStyle(isDropTargeted ? AnyShapeStyle(column.color) : AnyShapeStyle(.quaternary))
                    }
                    .animation(.easeOut(duration: 0.15), value: isDropTargeted)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(tasks) { task in
                            TaskCardView(
                                task: task,
                                isSelected: selectedTaskId == task.id,
                                isRunning: orchestrator?.runner(for: task.id) != nil,
                                onMoveTask: onMoveTask
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTaskId = task.id
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

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                // Agent badge
                HStack(spacing: 3) {
                    Image(systemName: task.agentType.icon)
                    Text(task.agentType.rawValue.capitalized)
                }
                .font(.system(size: 9, weight: .semibold))
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
                .font(.system(.caption, weight: .semibold))
                .lineLimit(2)

            Text(task.description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                if task.priority > 0 {
                    Text("P\(task.priority)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.forgeAmber)
                        .help("Priority \(task.priority) (1=low, 10=critical)")
                }
                Spacer()
                if let duration = task.durationMs {
                    Text(ForgeDuration.format(ms: duration))
                        .font(.system(size: 9, design: .monospaced))
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
    }
}

