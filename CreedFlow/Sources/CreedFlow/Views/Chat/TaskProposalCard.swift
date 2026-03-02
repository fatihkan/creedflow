import SwiftUI

/// Inline card showing a task proposal from the AI, with approve/reject actions.
struct TaskProposalCard: View {
    let proposal: TaskProposal
    let onApprove: () -> Void
    let onReject: () -> Void

    private var isPending: Bool { proposal.status == "pending" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.forgeAmber)

                Text("Task Proposal")
                    .font(.system(.subheadline, weight: .semibold))

                Spacer()

                statusBadge
            }

            Divider()

            // Features & tasks
            ForEach(Array(proposal.features.enumerated()), id: \.offset) { _, feature in
                VStack(alignment: .leading, spacing: 6) {
                    Text(feature.name)
                        .font(.system(.footnote, weight: .semibold))

                    ForEach(Array(feature.tasks.enumerated()), id: \.offset) { _, task in
                        taskRow(task)
                    }
                }
            }

            // Actions
            if isPending {
                Divider()
                HStack(spacing: 10) {
                    Spacer()
                    Button("Reject") {
                        onReject()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Approve & Create Tasks") {
                        onApprove()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.forgeSuccess)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.forgeAmber.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.forgeAmber.opacity(0.2), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch proposal.status {
            case "approved": return ("Approved", .forgeSuccess)
            case "rejected": return ("Rejected", .forgeDanger)
            default: return ("Pending", .forgeAmber)
            }
        }()

        Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func taskRow(_ task: TaskProposal.TaskProposalItem) -> some View {
        let agentType = parseAgentType(task.agentType)
        return HStack(spacing: 8) {
            Circle()
                .fill(agentType.themeColor)
                .frame(width: 6, height: 6)

            Text(task.title)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(agentType.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }

    private func parseAgentType(_ raw: String) -> AgentTask.AgentType {
        switch raw.lowercased() {
        case "coder": return .coder
        case "devops": return .devops
        case "tester": return .tester
        case "reviewer": return .reviewer
        case "contentwriter": return .contentWriter
        case "designer": return .designer
        case "imagegenerator": return .imageGenerator
        case "videoeditor": return .videoEditor
        case "publisher": return .publisher
        case "analyzer": return .analyzer
        case "monitor": return .monitor
        default: return .coder
        }
    }
}
