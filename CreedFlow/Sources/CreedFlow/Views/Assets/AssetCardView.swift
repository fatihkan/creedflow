import SwiftUI

struct AssetCardView: View {
    let asset: GeneratedAsset
    let projectName: String?
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.03))

                if let thumbnailPath = asset.thumbnailPath,
                   let nsImage = NSImage(contentsOfFile: thumbnailPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 100)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: iconForAssetType(asset.assetType))
                            .font(.system(size: 28))
                            .foregroundStyle(colorForAssetType(asset.assetType).opacity(0.6))
                        Text(fileExtension)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                    }
                }
            }
            .frame(height: 100)

            // Info area
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.name)
                    .font(.system(.caption, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    // Agent badge
                    Text(asset.agentType.rawValue.capitalized)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(asset.agentType.themeColor)

                    Spacer()

                    // Version
                    if asset.version > 1 {
                        Text("v\(asset.version)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.forgeAmber)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.forgeAmber.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 4) {
                    if let size = asset.fileSize {
                        Text(formatFileSize(size))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                    Spacer()
                    // Status dot
                    Circle()
                        .fill(colorForStatus(asset.status))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(8)
        }
        .forgeCard(selected: isSelected, hovered: isHovered, cornerRadius: 8)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button {
                NSWorkspace.shared.selectFile(asset.filePath, inFileViewerRootedAtPath: "")
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: asset.filePath))
            } label: {
                Label("Open", systemImage: "arrow.up.forward.square")
            }
        }
    }

    // MARK: - Helpers

    private var fileExtension: String {
        (asset.name as NSString).pathExtension.uppercased()
    }

    private func iconForAssetType(_ type: GeneratedAsset.AssetType) -> String {
        switch type {
        case .document: return "doc.text.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "waveform"
        case .design: return "paintbrush.fill"
        }
    }

    private func colorForAssetType(_ type: GeneratedAsset.AssetType) -> Color {
        switch type {
        case .document: return .blue
        case .image: return .green
        case .video: return .purple
        case .audio: return .orange
        case .design: return .pink
        }
    }

    private func colorForStatus(_ status: GeneratedAsset.Status) -> Color {
        switch status {
        case .generated: return .forgeNeutral
        case .reviewed: return .forgeInfo
        case .approved: return .forgeSuccess
        case .rejected: return .forgeDanger
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - List Row

struct AssetListRow: View {
    let asset: GeneratedAsset
    let projectName: String?

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: iconForType(asset.assetType))
                .font(.system(size: 16))
                .foregroundStyle(colorForType(asset.assetType))
                .frame(width: 28)

            // Name + agent
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.system(.subheadline, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(asset.agentType.rawValue.capitalized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let projectName {
                        Text(projectName)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Version badge
            if asset.version > 1 {
                Text("v\(asset.version)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.forgeAmber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.forgeAmber.opacity(0.12), in: Capsule())
            }

            // Size
            if let size = asset.fileSize {
                Text(formatSize(size))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 60, alignment: .trailing)
            }

            // Date
            Text(asset.createdAt, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func iconForType(_ type: GeneratedAsset.AssetType) -> String {
        switch type {
        case .document: return "doc.text.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "waveform"
        case .design: return "paintbrush.fill"
        }
    }

    private func colorForType(_ type: GeneratedAsset.AssetType) -> Color {
        switch type {
        case .document: return .blue
        case .image: return .green
        case .video: return .purple
        case .audio: return .orange
        case .design: return .pink
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
