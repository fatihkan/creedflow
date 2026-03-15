import SwiftUI
import GRDB

/// Interactive DAG viewer for task dependencies using SwiftUI Canvas.
struct TaskDependencyGraphView: View {
    let projectId: UUID
    let appDatabase: AppDatabase?

    @State private var tasks: [AgentTask] = []
    @State private var dependencies: [TaskDependency] = []
    @State private var nodePositions: [UUID: CGPoint] = [:]
    @State private var hoveredNode: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Dependency Graph")
                    .font(.headline)
                Spacer()
                Text("\(tasks.count) tasks · \(dependencies.count) edges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.forgeAmber)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            if tasks.isEmpty {
                Text("No tasks in this project")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Canvas { context, size in
                        drawEdges(context: context)
                        drawNodes(context: context)
                    }
                    .frame(width: canvasWidth, height: canvasHeight)
                    .overlay {
                        // Interactive overlay for hover/tooltip
                        ForEach(tasks, id: \.id) { task in
                            if let pos = nodePositions[task.id] {
                                nodeOverlay(task: task, at: pos)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            await loadData()
            layoutNodes()
        }
    }

    // MARK: - Layout

    private var canvasWidth: CGFloat {
        let cols = max(1, levelCount)
        return CGFloat(cols) * 180 + 100
    }

    private var canvasHeight: CGFloat {
        let maxPerLevel = levels.values.map(\.count).max() ?? 1
        return CGFloat(maxPerLevel) * 80 + 100
    }

    private var levelCount: Int { levels.keys.count }

    /// Assign tasks to levels via topological ordering
    private var levels: [Int: [AgentTask]] {
        // Build adjacency: task → tasks it depends on
        var inDegree: [UUID: Int] = [:]
        var dependents: [UUID: [UUID]] = [:] // dependsOn → [tasks that depend on it]
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        for task in tasks {
            inDegree[task.id] = 0
        }
        for dep in dependencies {
            inDegree[dep.taskId, default: 0] += 1
            dependents[dep.dependsOnTaskId, default: []].append(dep.taskId)
        }

        var queue = tasks.filter { (inDegree[$0.id] ?? 0) == 0 }.map(\.id)
        var taskLevel: [UUID: Int] = [:]
        for id in queue { taskLevel[id] = 0 }

        var visited = Set<UUID>()
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if visited.contains(current) { continue }
            visited.insert(current)
            let level = taskLevel[current] ?? 0

            for next in dependents[current] ?? [] {
                taskLevel[next] = max(taskLevel[next] ?? 0, level + 1)
                inDegree[next, default: 0] -= 1
                if inDegree[next] == 0 {
                    queue.append(next)
                }
            }
        }

        // Include orphan tasks (no deps)
        for task in tasks where taskLevel[task.id] == nil {
            taskLevel[task.id] = 0
        }

        var result: [Int: [AgentTask]] = [:]
        for (id, level) in taskLevel {
            if let task = taskMap[id] {
                result[level, default: []].append(task)
            }
        }
        // Sort within each level by priority
        for key in result.keys {
            result[key]?.sort { $0.priority > $1.priority }
        }
        return result
    }

    private func layoutNodes() {
        var positions: [UUID: CGPoint] = [:]
        let sortedLevels = levels.keys.sorted()

        for level in sortedLevels {
            let tasksAtLevel = levels[level] ?? []
            for (index, task) in tasksAtLevel.enumerated() {
                let x = CGFloat(level) * 180 + 90
                let y = CGFloat(index) * 80 + 60
                positions[task.id] = CGPoint(x: x, y: y)
            }
        }
        nodePositions = positions
    }

    // MARK: - Drawing

    private func drawEdges(context: GraphicsContext) {
        for dep in dependencies {
            guard let from = nodePositions[dep.dependsOnTaskId],
                  let to = nodePositions[dep.taskId] else { continue }

            var path = Path()
            path.move(to: CGPoint(x: from.x + 28, y: from.y))

            let midX = (from.x + to.x) / 2
            path.addCurve(
                to: CGPoint(x: to.x - 28, y: to.y),
                control1: CGPoint(x: midX, y: from.y),
                control2: CGPoint(x: midX, y: to.y)
            )

            context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)

            // Arrow head
            let angle = atan2(to.y - from.y, to.x - from.x)
            let arrowTip = CGPoint(x: to.x - 28, y: to.y)
            var arrowPath = Path()
            arrowPath.move(to: arrowTip)
            arrowPath.addLine(to: CGPoint(
                x: arrowTip.x - 8 * cos(angle - .pi / 6),
                y: arrowTip.y - 8 * sin(angle - .pi / 6)
            ))
            arrowPath.move(to: arrowTip)
            arrowPath.addLine(to: CGPoint(
                x: arrowTip.x - 8 * cos(angle + .pi / 6),
                y: arrowTip.y - 8 * sin(angle + .pi / 6)
            ))
            context.stroke(arrowPath, with: .color(.secondary.opacity(0.6)), lineWidth: 1.5)
        }
    }

    private func drawNodes(context: GraphicsContext) {
        for task in tasks {
            guard let pos = nodePositions[task.id] else { continue }
            let rect = CGRect(x: pos.x - 24, y: pos.y - 24, width: 48, height: 48)
            let path = Circle().path(in: rect)

            context.fill(path, with: .color(statusColor(task.status).opacity(0.15)))
            context.stroke(path, with: .color(statusColor(task.status)), lineWidth: hoveredNode == task.id ? 3 : 2)

            // Agent type initial
            let initial = String(task.agentType.rawValue.prefix(1)).uppercased()
            context.draw(
                Text(initial).font(.system(size: 16, weight: .bold)).foregroundColor(statusColor(task.status)),
                at: pos
            )
        }
    }

    private func nodeOverlay(task: AgentTask, at pos: CGPoint) -> some View {
        Circle()
            .fill(Color.clear)
            .frame(width: 48, height: 48)
            .position(pos)
            .onHover { hovering in hoveredNode = hovering ? task.id : nil }
            .popover(isPresented: Binding(
                get: { hoveredNode == task.id },
                set: { if !$0 { hoveredNode = nil } }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(task.agentType.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(task.status.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(statusColor(task.status))
                    }
                }
                .padding(8)
                .frame(maxWidth: 200)
            }
    }

    private func statusColor(_ status: AgentTask.Status) -> Color {
        switch status {
        case .queued: return .gray
        case .inProgress: return .blue
        case .passed: return .green
        case .failed: return .red
        case .needsRevision: return .orange
        case .cancelled: return .gray.opacity(0.5)
        }
    }

    // MARK: - Data

    private func loadData() async {
        guard let db = appDatabase else { return }
        do {
            let result = try await db.dbQueue.read { db -> ([AgentTask], [TaskDependency]) in
                let tasks = try AgentTask
                    .filter(Column("projectId") == projectId)
                    .filter(Column("archivedAt") == nil)
                    .order(Column("priority").desc)
                    .fetchAll(db)
                let taskIds = tasks.map(\.id)
                let deps = try TaskDependency
                    .filter(taskIds.contains(Column("taskId")))
                    .fetchAll(db)
                return (tasks, deps)
            }
            tasks = result.0
            dependencies = result.1
        } catch {
            // silently fail for graph
        }
    }
}
