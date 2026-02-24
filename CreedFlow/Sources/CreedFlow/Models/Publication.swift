import Foundation
import GRDB

/// Tracks content published to external platforms (Medium, WordPress, Twitter, etc.).
package struct Publication: Codable, Identifiable, Equatable {
    package var id: UUID
    package var assetId: UUID
    package var projectId: UUID
    package var channelId: UUID
    package var status: Status
    package var externalId: String?
    package var publishedUrl: String?
    package var scheduledAt: Date?
    package var publishedAt: Date?
    package var errorMessage: String?
    package var exportFormat: ExportFormat
    package var createdAt: Date
    package var updatedAt: Date

    package enum Status: String, Codable, CaseIterable, DatabaseValueConvertible {
        case scheduled
        case publishing
        case published
        case failed
    }

    package enum ExportFormat: String, Codable, CaseIterable, DatabaseValueConvertible {
        case markdown
        case html
        case plaintext
        case pdf
    }

    package init(
        id: UUID = UUID(),
        assetId: UUID,
        projectId: UUID,
        channelId: UUID,
        status: Status = .scheduled,
        externalId: String? = nil,
        publishedUrl: String? = nil,
        scheduledAt: Date? = nil,
        publishedAt: Date? = nil,
        errorMessage: String? = nil,
        exportFormat: ExportFormat = .markdown,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.assetId = assetId
        self.projectId = projectId
        self.channelId = channelId
        self.status = status
        self.externalId = externalId
        self.publishedUrl = publishedUrl
        self.scheduledAt = scheduledAt
        self.publishedAt = publishedAt
        self.errorMessage = errorMessage
        self.exportFormat = exportFormat
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension Publication: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "publication"

    static let asset = belongsTo(GeneratedAsset.self, using: ForeignKey(["assetId"]))
    static let project = belongsTo(Project.self)
    static let channel = belongsTo(PublishingChannel.self, using: ForeignKey(["channelId"]))
}
