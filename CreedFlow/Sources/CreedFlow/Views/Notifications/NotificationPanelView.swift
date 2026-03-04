import SwiftUI

/// Full notification panel shown as a popover from the sidebar bell icon.
/// Shows recent notifications with category badges, swipe-to-dismiss, and mark-all-read.
struct NotificationPanelView: View {
    @Bindable var viewModel: NotificationViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L("notifications.title"))
                    .font(.headline)
                Spacer()
                if viewModel.unreadCount > 0 {
                    Button(L("notifications.markAllRead")) {
                        viewModel.markAllRead()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                if !viewModel.recentNotifications.isEmpty {
                    Button {
                        viewModel.clearAll()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.7))
                    .help(L("notifications.clearAll"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Notification list
            if viewModel.recentNotifications.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(L("notifications.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.recentNotifications) { notification in
                            NotificationRow(
                                notification: notification,
                                onRead: { viewModel.markRead(notification.id) },
                                onDelete: { viewModel.deleteOne(notification.id) }
                            )
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 480)
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let notification: AppNotification
    let onRead: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notification.severity.icon)
                .font(.system(size: 14))
                .foregroundStyle(notification.severity.color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(notification.category.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(notification.category.badgeColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(notification.category.badgeColor)

                    Spacer()

                    Text(notification.createdAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Text(notification.title)
                    .font(.system(size: 12, weight: notification.isRead ? .regular : .semibold))
                    .lineLimit(1)

                Text(notification.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("notifications.delete"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(notification.isRead ? Color.clear : Color.blue.opacity(0.04))
        .contentShape(Rectangle())
        .onTapGesture {
            if !notification.isRead {
                onRead()
            }
        }
    }
}
