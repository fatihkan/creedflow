import Foundation
import GRDB

/// Manages file storage and DB records for assets produced by creative agents.
actor AssetStorageService {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Save text content as a file and create a DB record.
    func saveTextAsset(
        content: String,
        fileName: String,
        project: Project,
        task: AgentTask,
        assetType: GeneratedAsset.AssetType,
        mimeType: String? = nil
    ) throws -> GeneratedAsset {
        let dir = assetsDirectory(for: project)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let filePath = (dir as NSString).appendingPathComponent(fileName)
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int64) ?? Int64(content.utf8.count)

        let resolvedMime = mimeType ?? mimeTypeForExtension(fileName)
        var asset = GeneratedAsset(
            projectId: project.id,
            taskId: task.id,
            agentType: task.agentType,
            assetType: assetType,
            name: fileName,
            filePath: filePath,
            mimeType: resolvedMime,
            fileSize: fileSize
        )
        try dbQueue.write { db in
            try asset.insert(db)
        }
        return asset
    }

    /// Download a file from a URL and create a DB record.
    func downloadAndSaveAsset(
        url: URL,
        fileName: String,
        project: Project,
        task: AgentTask,
        assetType: GeneratedAsset.AssetType
    ) async throws -> GeneratedAsset {
        let dir = assetsDirectory(for: project)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let filePath = (dir as NSString).appendingPathComponent(fileName)

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: filePath))

        let httpResponse = response as? HTTPURLResponse
        let responseMime = httpResponse?.mimeType
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int64) ?? 0
        let resolvedMime = responseMime ?? mimeTypeForExtension(fileName)

        var asset = GeneratedAsset(
            projectId: project.id,
            taskId: task.id,
            agentType: task.agentType,
            assetType: assetType,
            name: fileName,
            filePath: filePath,
            mimeType: resolvedMime,
            fileSize: fileSize,
            sourceUrl: url.absoluteString
        )
        try await dbQueue.write { db in
            try asset.insert(db)
        }
        return asset
    }

    /// Register a pre-existing file as an asset in the DB.
    func recordExistingAsset(
        filePath: String,
        project: Project,
        task: AgentTask,
        assetType: GeneratedAsset.AssetType
    ) throws -> GeneratedAsset {
        let fileName = (filePath as NSString).lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int64) ?? 0
        let resolvedMime = mimeTypeForExtension(fileName)

        var asset = GeneratedAsset(
            projectId: project.id,
            taskId: task.id,
            agentType: task.agentType,
            assetType: assetType,
            name: fileName,
            filePath: filePath,
            mimeType: resolvedMime,
            fileSize: fileSize
        )
        try dbQueue.write { db in
            try asset.insert(db)
        }
        return asset
    }

    /// List assets, optionally filtered by project and/or type.
    func listAssets(projectId: UUID? = nil, assetType: GeneratedAsset.AssetType? = nil) throws -> [GeneratedAsset] {
        try dbQueue.read { db in
            var request = GeneratedAsset.order(Column("createdAt").desc)
            if let projectId {
                request = request.filter(Column("projectId") == projectId)
            }
            if let assetType {
                request = request.filter(Column("assetType") == assetType.rawValue)
            }
            return try request.fetchAll(db)
        }
    }

    /// Update the status of an asset (e.g. after review).
    func updateStatus(assetId: UUID, status: GeneratedAsset.Status) throws {
        try dbQueue.write { db in
            guard var asset = try GeneratedAsset.fetchOne(db, id: assetId) else { return }
            asset.status = status
            asset.updatedAt = Date()
            try asset.update(db)
        }
    }

    /// Link assets to a review task.
    func linkToReviewTask(taskId: UUID, reviewTaskId: UUID) throws {
        _ = try dbQueue.write { db in
            try GeneratedAsset
                .filter(Column("taskId") == taskId)
                .updateAll(db,
                    Column("reviewTaskId").set(to: reviewTaskId),
                    Column("updatedAt").set(to: Date())
                )
        }
    }

    // MARK: - Private

    private func assetsDirectory(for project: Project) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/CreedFlow/projects/\(project.name)/assets"
    }

    private func mimeTypeForExtension(_ fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "ogg": return "audio/ogg"
        case "pdf": return "application/pdf"
        case "md": return "text/markdown"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "html": return "text/html"
        case "css": return "text/css"
        default: return "application/octet-stream"
        }
    }
}
