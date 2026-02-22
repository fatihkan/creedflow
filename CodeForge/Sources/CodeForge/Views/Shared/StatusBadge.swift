import SwiftUI

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status.lowercased() {
        case "queued", "pending", "planning":
            return .gray
        case "in_progress", "inprogress", "analyzing":
            return .blue
        case "passed", "completed", "success", "healthy":
            return .green
        case "failed", "unhealthy":
            return .red
        case "needs_revision", "reviewing", "degraded":
            return .orange
        case "cancelled", "paused":
            return .secondary
        default:
            return .secondary
        }
    }
}

struct AgentTypeBadge: View {
    let type: AgentTask.AgentType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(type.rawValue.capitalized)
        }
        .font(.caption2.bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private var icon: String {
        switch type {
        case .analyzer: return "magnifyingglass"
        case .coder: return "chevron.left.forwardslash.chevron.right"
        case .reviewer: return "checkmark.shield"
        case .tester: return "testtube.2"
        case .devops: return "server.rack"
        case .monitor: return "waveform.path.ecg"
        }
    }

    private var color: Color {
        switch type {
        case .analyzer: return .purple
        case .coder: return .blue
        case .reviewer: return .orange
        case .tester: return .green
        case .devops: return .cyan
        case .monitor: return .pink
        }
    }
}

struct TaskRowCompactView: View {
    let task: AgentTask

    var body: some View {
        HStack {
            AgentTypeBadge(type: task.agentType)
            Text(task.title)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            StatusBadge(status: task.status.rawValue)
        }
        .padding(.vertical, 2)
    }
}
