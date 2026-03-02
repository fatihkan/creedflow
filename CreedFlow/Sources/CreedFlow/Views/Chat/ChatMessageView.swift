import SwiftUI

/// Displays a single chat message with avatar, content, and optional task proposal.
struct ChatMessageView: View {
    let message: ProjectMessage
    let chatService: ProjectChatService

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                // Header row
                HStack(spacing: 6) {
                    Text(roleLabel)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(roleColor)

                    if let backend = message.backend,
                       let type = CLIBackendType(rawValue: backend) {
                        Text(type.displayName)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(type.backendColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(type.backendColor.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    Text(message.createdAt, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // Content
                Text(displayContent)
                    .font(.system(.body))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                // Task proposal card
                if let proposal = parsedProposal {
                    TaskProposalCard(
                        proposal: proposal,
                        onApprove: {
                            Task { await chatService.approveProposal(messageId: message.id) }
                        },
                        onReject: {
                            Task { await chatService.rejectProposal(messageId: message.id) }
                        }
                    )
                    .padding(.top, 4)
                }

                // Cost info
                if let cost = message.costUSD, cost > 0 {
                    Text(String(format: "$%.4f", cost))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Computed

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "AI"
        case .system: return "System"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: return .forgeInfo
        case .assistant: return .forgeAmber
        case .system: return .forgeNeutral
        }
    }

    @ViewBuilder
    private var avatar: some View {
        Circle()
            .fill(roleColor.opacity(0.15))
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: avatarIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(roleColor)
            }
    }

    private var avatarIcon: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "brain"
        case .system: return "gearshape"
        }
    }

    /// Strip the JSON code block from displayed content when a proposal exists.
    private var displayContent: String {
        guard parsedProposal != nil else { return message.content }

        // Remove ```json ... ``` block from display
        var content = message.content
        if let jsonStart = content.range(of: "```json"),
           let jsonEnd = content.range(of: "```", range: jsonStart.upperBound..<content.endIndex) {
            let endOfBlock = content.index(after: jsonEnd.upperBound)
            let blockEnd = min(endOfBlock, content.endIndex)
            content.removeSubrange(jsonStart.lowerBound..<blockEnd)
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedProposal: TaskProposal? {
        guard let metadata = message.metadata,
              let data = metadata.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TaskProposal.self, from: data)
    }
}
