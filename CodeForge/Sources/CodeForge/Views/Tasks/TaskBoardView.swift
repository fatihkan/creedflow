import SwiftUI
import GRDB

/// Kanban-style board showing tasks grouped by status with real-time updates.
struct TaskBoardView: View {
    let projectId: UUID
    @Binding var selectedTaskId: UUID?
    let appDatabase: AppDatabase?
    let orchestrator: Orchestrator?

    @State private var tasks: [AgentTask] = []
    @State private var errorMessage: String?

    private let columns: [KanbanColumn] = [
        KanbanColumn(title: "Queued", status: .queued, color: .forgeNeutral),
        KanbanColumn(title: "In Progress", status: .inProgress, color: .forgeInfo),
        KanbanColumn(title: "Review", status: .needsRevision, color: .forgeWarning),
        KanbanColumn(title: "Done", status: .passed, color: .forgeSuccess),
        KanbanColumn(title: "Failed", status: .failed, color: .forgeDanger),
    ]

    var body: some View {
        VStack(spacing: 0) {
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
                            orchestrator: orchestrator
                        )
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Task Board")
        .task(id: projectId) {
            await observeTasks()
        }
    }

    private func observeTasks() async {
        guard let db = appDatabase else { return }
        let pid = projectId
        let observation = ValueObservation.tracking { db in
            try AgentTask
                .filter(Column("projectId") == pid)
                .order(Column("priority").desc, Column("createdAt").asc)
                .fetchAll(db)
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                tasks = value
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Column header
            HStack(spacing: 6) {
                Circle()
                    .fill(column.color)
                    .frame(width: 8, height: 8)
                Text(column.title)
                    .font(.system(.subheadline, weight: .semibold))
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

            // Task cards
            if tasks.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.3))
                    .frame(height: 60)
                    .overlay {
                        Text("No tasks")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(tasks) { task in
                            TaskCardView(
                                task: task,
                                isSelected: selectedTaskId == task.id,
                                isRunning: orchestrator?.runner(for: task.id) != nil
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTaskId = task.id
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 240)
    }
}

struct TaskCardView: View {
    let task: AgentTask
    let isSelected: Bool
    var isRunning: Bool = false

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
                }
                Spacer()
                if let cost = task.costUSD {
                    Text(String(format: "$%.4f", cost))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                if let duration = task.durationMs {
                    Text(ForgeDuration.format(ms: duration))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .forgeCard(selected: isSelected, cornerRadius: 8)
    }
}
