import SwiftUI
import GRDB

struct AssetDetailSheet: View {
    let asset: GeneratedAsset
    let projectName: String?
    let appDatabase: AppDatabase?

    @Environment(\.dismiss) private var dismiss
    @State private var versionHistory: [GeneratedAsset] = []
    @State private var formatVariants: [GeneratedAsset] = []
    @State private var previewText: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.system(.title3, weight: .semibold))
                    HStack(spacing: 8) {
                        Text(asset.agentType.rawValue.capitalized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(asset.agentType.themeColor)
                        if let projectName {
                            Text(projectName)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Text("v\(asset.version)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.forgeAmber)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.forgeAmber.opacity(0.12), in: Capsule())
                    }
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Preview
                    previewSection

                    // Metadata
                    metadataSection

                    // Format Variants
                    if !formatVariants.isEmpty {
                        variantsSection
                    }

                    // Version History
                    if versionHistory.count > 1 {
                        versionSection
                    }
                }
                .padding(16)
            }

            Divider()

            // Actions
            HStack(spacing: 10) {
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
                Spacer()
            }
            .padding(12)
        }
        .frame(width: 520, height: 580)
        .task {
            loadPreview()
            await loadVersionHistory()
            await loadFormatVariants()
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        Group {
            if let thumbnailPath = asset.thumbnailPath,
               let nsImage = NSImage(contentsOfFile: thumbnailPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let text = previewText {
                ScrollView {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 180)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                        }
                }
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                metaRow("Type", value: asset.assetType.rawValue.capitalized)
                metaRow("Status", value: asset.status.rawValue.capitalized)
                metaRow("Size", value: formatFileSize(asset.fileSize ?? 0))
                metaRow("MIME", value: asset.mimeType ?? "unknown")
                metaRow("Created", value: asset.createdAt.formatted(.dateTime.month().day().hour().minute()))
                if let checksum = asset.checksum {
                    metaRow("SHA256", value: String(checksum.prefix(16)) + "...")
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
        }
    }

    private func metaRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)
        }
    }

    // MARK: - Format Variants

    private var variantsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format Variants")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(formatVariants, id: \.id) { variant in
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: variant.filePath))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: iconForMime(variant.mimeType))
                                .font(.system(size: 11))
                            Text(extensionFromName(variant.name))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .textCase(.uppercase)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Open \(variant.name)")
                }
            }
        }
    }

    // MARK: - Version History

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Version History")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(versionHistory.reversed(), id: \.id) { version in
                HStack(spacing: 10) {
                    // Version indicator
                    ZStack {
                        Circle()
                            .fill(version.id == asset.id ? Color.forgeAmber.opacity(0.15) : Color.primary.opacity(0.05))
                            .frame(width: 28, height: 28)
                        Text("v\(version.version)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(version.id == asset.id ? .forgeAmber : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(version.id == asset.id ? "Current" : "")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.forgeAmber)
                            Text(version.createdAt, style: .relative)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Text(formatFileSize(version.fileSize ?? 0))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }

                    Spacer()

                    if version.id != asset.id {
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: version.filePath))
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open v\(version.version)")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Data Loading

    private func loadPreview() {
        let textMimes = ["text/markdown", "text/plain", "text/html", "application/json", "text/css"]
        guard let mime = asset.mimeType, textMimes.contains(mime) else { return }
        if let content = try? String(contentsOfFile: asset.filePath, encoding: .utf8) {
            previewText = String(content.prefix(2000))
        }
    }

    private func loadVersionHistory() async {
        guard let db = appDatabase else { return }
        versionHistory = (try? await db.dbQueue.read { db in
            try GeneratedAsset
                .filter(Column("name") == asset.name)
                .filter(Column("projectId") == asset.projectId)
                .order(Column("version").asc)
                .fetchAll(db)
        }) ?? []
    }

    private func loadFormatVariants() async {
        guard let db = appDatabase else { return }
        let baseName = (asset.name as NSString).deletingPathExtension
        formatVariants = (try? await db.dbQueue.read { db in
            try GeneratedAsset
                .filter(Column("taskId") == asset.taskId)
                .filter(Column("assetType") == GeneratedAsset.AssetType.document.rawValue)
                .filter(Column("version") == asset.version)
                .filter(Column("id") != asset.id)
                .order(Column("name").asc)
                .fetchAll(db)
                .filter { ($0.name as NSString).deletingPathExtension == baseName }
        }) ?? []
    }

    // MARK: - Helpers

    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func extensionFromName(_ name: String) -> String {
        (name as NSString).pathExtension
    }

    private func iconForMime(_ mime: String?) -> String {
        switch mime {
        case "text/markdown": return "doc.text"
        case "text/plain": return "doc.plaintext"
        case "text/html": return "globe"
        case "application/pdf": return "doc.richtext"
        case "application/json": return "curlybraces"
        default: return "doc"
        }
    }
}
