import Foundation
import AppKit
import QuickLookThumbnailing

/// Generates preview thumbnails for assets (images, PDFs, text files).
actor ThumbnailGeneratorService {
    private let thumbnailSize = CGSize(width: 200, height: 200)

    /// Generate a thumbnail for the given asset and return the thumbnail file path.
    /// Returns nil if the asset type is not previewable.
    func generateThumbnail(for asset: GeneratedAsset, projectName: String) async -> String? {
        let thumbDir = thumbnailDirectory(for: projectName)
        try? FileManager.default.createDirectory(atPath: thumbDir, withIntermediateDirectories: true)

        let thumbFileName = "\(asset.id.uuidString)_thumb.png"
        let thumbPath = (thumbDir as NSString).appendingPathComponent(thumbFileName)

        // Skip if thumbnail already exists
        if FileManager.default.fileExists(atPath: thumbPath) {
            return thumbPath
        }

        let fileURL = URL(fileURLWithPath: asset.filePath)

        // Use QuickLook for supported file types (images, PDFs, video stills)
        if let image = await generateQLThumbnail(for: fileURL) {
            if savePNG(image: image, to: thumbPath) {
                return thumbPath
            }
        }

        // Fallback: text-based preview for text files
        if isTextFile(asset: asset) {
            if let image = generateTextPreview(for: fileURL) {
                if savePNG(image: image, to: thumbPath) {
                    return thumbPath
                }
            }
        }

        return nil
    }

    // MARK: - Private

    private func generateQLThumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: thumbnailSize,
            scale: 2.0,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }

    private func generateTextPreview(for url: URL) -> NSImage? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let preview = String(text.prefix(500))

        let image = NSImage(size: thumbnailSize)
        image.lockFocus()

        NSColor.white.setFill()
        NSRect(origin: .zero, size: thumbnailSize).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]
        let rect = NSRect(x: 4, y: 4, width: thumbnailSize.width - 8, height: thumbnailSize.height - 8)
        (preview as NSString).draw(in: rect, withAttributes: attrs)

        image.unlockFocus()
        return image
    }

    private func savePNG(image: NSImage, to path: String) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        return FileManager.default.createFile(atPath: path, contents: pngData)
    }

    private func isTextFile(asset: GeneratedAsset) -> Bool {
        let textMimes = ["text/plain", "text/markdown", "text/html", "text/css", "application/json"]
        if let mime = asset.mimeType, textMimes.contains(mime) { return true }
        let textExts = ["md", "txt", "json", "html", "css", "swift", "py", "js", "ts"]
        let ext = (asset.filePath as NSString).pathExtension.lowercased()
        return textExts.contains(ext)
    }

    private func thumbnailDirectory(for projectName: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/CreedFlow/projects/\(projectName)/thumbnails"
    }
}
