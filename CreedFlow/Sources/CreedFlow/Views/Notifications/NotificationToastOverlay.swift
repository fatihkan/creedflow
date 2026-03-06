import SwiftUI

/// Overlay that displays toast notifications in the top-right corner.
/// Auto-dismisses each toast after 5 seconds with a slide-in animation.
struct NotificationToastOverlay: View {
    @Bindable var viewModel: NotificationViewModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(viewModel.pendingToasts, id: \.id) { toast in
                // accessibility: role=status for toast notifications
                ToastCard(notification: toast) {
                    viewModel.removeToast(toast.id)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.top, 12)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.spring(response: 0.3), value: viewModel.pendingToasts.count)
    }
}

// MARK: - Toast Card

private struct ToastCard: View {
    let notification: AppNotification
    let onDismiss: () -> Void
    @State private var isVisible = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notification.severity.icon)
                .font(.system(size: 16))
                .foregroundStyle(notification.severity.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(notification.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 320)
        .accessibilityElement(children: .combine)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(notification.severity.color.opacity(0.3), lineWidth: 0.5)
        }
        .onAppear {
            // Auto-dismiss after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                onDismiss()
            }
        }
    }
}
