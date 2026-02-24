import Foundation
import GRDB
import CryptoKit

/// Manages asset version lineage — creating new versions, querying history, restoring.
actor AssetVersioningService {
    private let dbQueue: DatabaseQueue
    private let storageBackend: any AssetStorageBackend

    init(dbQueue: DatabaseQueue, storageBackend: any AssetStorageBackend = LocalAssetStorageBackend()) {
        self.dbQueue = dbQueue
        self.storageBackend = storageBackend
    }

    /// Create a new version of an existing asset.
    /// The original asset is preserved; a new record is created with incremented version.
    func createVersion(
        of assetId: UUID,
        newFilePath: String,
        task: AgentTask
    ) throws -> GeneratedAsset {
        try dbQueue.write { db in
            guard let original = try GeneratedAsset.fetchOne(db, id: assetId) else {
                throw AssetVersionError.assetNotFound(assetId)
            }

            // Find the current max version for this asset lineage
            let maxVersion = try Int.fetchOne(db, sql: """
                SELECT MAX(version) FROM generatedAsset
                WHERE name = ? AND projectId = ?
                """, arguments: [original.name, original.projectId.uuidString]) ?? original.version

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: newFilePath)[.size] as? Int64) ?? 0
            let checksum = Self.computeChecksum(filePath: newFilePath)

            var newAsset = GeneratedAsset(
                projectId: original.projectId,
                taskId: task.id,
                agentType: task.agentType,
                assetType: original.assetType,
                name: original.name,
                assetDescription: original.assetDescription,
                filePath: newFilePath,
                mimeType: original.mimeType,
                fileSize: fileSize,
                sourceUrl: nil,
                metadata: original.metadata,
                version: maxVersion + 1,
                checksum: checksum,
                parentAssetId: assetId
            )
            try newAsset.insert(db)
            return newAsset
        }
    }

    /// Return all versions of an asset in ascending order.
    func versionHistory(for assetId: UUID) throws -> [GeneratedAsset] {
        try dbQueue.read { db in
            guard let asset = try GeneratedAsset.fetchOne(db, id: assetId) else {
                return []
            }
            // Find all versions by matching name + projectId
            return try GeneratedAsset
                .filter(Column("name") == asset.name)
                .filter(Column("projectId") == asset.projectId)
                .order(Column("version").asc)
                .fetchAll(db)
        }
    }

    /// Compute SHA256 checksum of a file.
    static func computeChecksum(filePath: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum AssetVersionError: Error, LocalizedError {
    case assetNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .assetNotFound(let id): return "Asset not found: \(id)"
        }
    }
}
