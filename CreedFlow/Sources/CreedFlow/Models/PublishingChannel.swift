import Foundation
import GRDB

/// Configured publishing channel (Medium, WordPress, Twitter, etc.) with credentials.
package struct PublishingChannel: Codable, Identifiable, Equatable {
    package var id: UUID
    package var name: String
    package var channelType: ChannelType
    package var credentialsJSON: String   // JSON with API keys/tokens
    package var isEnabled: Bool
    package var defaultTags: String       // comma-separated
    package var createdAt: Date
    package var updatedAt: Date

    package enum ChannelType: String, Codable, CaseIterable, DatabaseValueConvertible {
        case medium
        case wordpress
        case twitter
        case linkedin
        case devTo
    }

    package init(
        id: UUID = UUID(),
        name: String,
        channelType: ChannelType,
        credentialsJSON: String = "{}",
        isEnabled: Bool = true,
        defaultTags: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.channelType = channelType
        self.credentialsJSON = credentialsJSON
        self.isEnabled = isEnabled
        self.defaultTags = defaultTags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension PublishingChannel: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "publishingChannel"

    static let publications = hasMany(Publication.self, using: ForeignKey(["channelId"]))
}
