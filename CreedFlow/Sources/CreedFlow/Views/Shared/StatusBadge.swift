import SwiftUI

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(displayText)
            .forgeBadge(color: color)
    }

    private var displayText: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var color: Color {
        switch status.lowercased() {
        case "queued", "pending", "planning":
            return .forgeNeutral
        case "in_progress", "inprogress", "analyzing":
            return .forgeInfo
        case "passed", "completed", "success", "healthy":
            return .forgeSuccess
        case "failed", "unhealthy":
            return .forgeDanger
        case "needs_revision", "reviewing", "degraded":
            return .forgeWarning
        case "cancelled", "paused":
            return .forgeNeutral.opacity(0.6)
        default:
            return .forgeNeutral
        }
    }
}

struct AgentTypeBadge: View {
    let type: AgentTask.AgentType

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: type.icon)
            Text(type.rawValue.capitalized)
        }
        .forgeBadge(color: type.themeColor)
    }
}

struct BackendBadge: View {
    let type: CLIBackendType

    var body: some View {
        Text(type.rawValue.capitalized)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch type {
        case .claude: return .forgeInfo
        case .codex: return .forgeSuccess
        case .gemini: return .forgeAmber
        case .opencode: return .teal
        case .ollama: return .orange
        case .lmstudio: return .cyan
        case .llamacpp: return .pink
        case .mlx: return .mint
        }
    }
}

struct TaskRowCompactView: View {
    let task: AgentTask

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(task.status.themeColor)
                .frame(width: 3, height: 20)

            AgentTypeBadge(type: task.agentType)

            Text(task.title)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Text(task.status.displayName)
                .forgeBadge(color: task.status.themeColor)
        }
        .padding(.vertical, 2)
    }
}
