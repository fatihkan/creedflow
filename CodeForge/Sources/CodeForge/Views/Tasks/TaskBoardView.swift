import SwiftUI
import GRDB

/// Kanban-style board showing tasks grouped by status
struct TaskBoardView: View {
    let projectId: UUID
    @Binding var selectedTaskId: UUID?
    let appDatabase: AppDatabase?

    @State private var tasks: [AgentTask] = []

    private let columns = [
        KanbanColumn(title: "Queued", status: .queued, color: .gray),
        KanbanColumn(title: "In Progress", status: .inProgress, color: .blue),
        KanbanColumn(title: "Review", status: .needsRevision, color: .orange),
        KanbanColumn(title: "Done", status: .passed, color: .green),
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(columns, id: \.title) { column in
                    KanbanColumnView(
                        column: column,
                        tasks: tasks.filter { $0.status == column.status },
                        selectedTaskId: $selectedTaskId
                    )
                }

                // Failed column (separate)
                KanbanColumnView(
                    column: KanbanColumn(title: "Failed", status: .failed, color: .red),
                    tasks: tasks.filter { $0.status == .failed },
                    selectedTaskId: $selectedTaskId
                )
            }
            .padding()
        }
        .navigationTitle("Task Board")
        .task {
            await loadTasks()
        }
    }

    private func loadTasks() async {
        guard let db = appDatabase else { return }
        do {
            tasks = try await db.dbQueue.read { db in
                try AgentTask
                    .filter(Column("projectId") == projectId)
                    .order(Column("priority").desc, Column("createdAt").asc)
                    .fetchAll(db)
            }
        } catch {}
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Column header
            HStack {
                Circle()
                    .fill(column.color)
                    .frame(width: 8, height: 8)
                Text(column.title)
                    .font(.headline)
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.background.secondary)
                    .clipShape(Capsule())
            }

            // Task cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        TaskCardView(task: task, isSelected: selectedTaskId == task.id)
                            .onTapGesture {
                                selectedTaskId = task.id
                            }
                    }
                }
            }
        }
        .frame(width: 250)
    }
}

struct TaskCardView: View {
    let task: AgentTask
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                AgentTypeBadge(type: task.agentType)
                Spacer()
                if task.status == .inProgress {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            Text(task.title)
                .font(.subheadline.bold())
                .lineLimit(2)

            Text(task.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text("P\(task.priority)")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                Spacer()
                if let cost = task.costUSD {
                    Text(String(format: "$%.4f", cost))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
    }
}
