import SwiftUI
import AppKit

struct UpdateBannerView: View {
    let updateInfo: UpdateInfo
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.forgeAmber)

            Text("CreedFlow v\(updateInfo.latestVersion) is available.")
                .font(.system(size: 12, weight: .medium))
            Text("You're on v\(updateInfo.currentVersion).")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                if let url = URL(string: updateInfo.releaseUrl) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("View Release")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.forgeAmber)
            }
            .buttonStyle(.plain)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.forgeAmber.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
