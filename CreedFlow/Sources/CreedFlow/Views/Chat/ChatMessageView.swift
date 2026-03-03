import SwiftUI
import AppKit

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

                // Attachments
                if let attachments = parsedAttachments, !attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(attachments, id: \.path) { attachment in
                            if attachment.isImage {
                                imageAttachmentView(attachment)
                            } else {
                                fileAttachmentBadge(attachment)
                            }
                        }
                    }
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
            content.removeSubrange(jsonStart.lowerBound..<jsonEnd.upperBound)
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedProposal: TaskProposal? {
        guard let metadata = message.metadata,
              let data = metadata.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TaskProposal.self, from: data)
    }

    private var parsedAttachments: [ChatAttachment]? {
        guard let metadata = message.metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let attachmentsArray = json["attachments"] else { return nil }
        let attachmentsData = try? JSONSerialization.data(withJSONObject: attachmentsArray)
        guard let attachmentsData else { return nil }
        return try? JSONDecoder().decode([ChatAttachment].self, from: attachmentsData)
    }

    @ViewBuilder
    private func imageAttachmentView(_ attachment: ChatAttachment) -> some View {
        let url = URL(fileURLWithPath: attachment.path)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }
        } else {
            fileAttachmentBadge(attachment)
        }
    }

    private func fileAttachmentBadge(_ attachment: ChatAttachment) -> some View {
        HStack(spacing: 4) {
            Image(systemName: attachment.isImage ? "photo" : "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(attachment.isImage ? Color.forgeInfo : Color.forgeAmber)
            Text(attachment.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}
