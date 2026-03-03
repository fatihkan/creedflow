import Foundation
import GRDB

/// In-app notification persisted to SQLite — covers backend health, MCP health,
/// rate limits, task lifecycle, deployments, and system events.
package struct AppNotification: Codable, Identifiable, Equatable {
    package var id: UUID
    package var category: Category
    package var severity: Severity
    package var title: String
    package var message: String
    package var metadata: String?
    package var isRead: Bool
    package var isDismissed: Bool
    package var createdAt: Date

    package enum Category: String, Codable, CaseIterable, DatabaseValueConvertible {
        case backendHealth
        case mcpHealth
        case rateLimit
        case task
        case deploy
        case system
    }

    package enum Severity: String, Codable, CaseIterable, DatabaseValueConvertible {
        case info
        case warning
        case error
        case success
    }

    package init(
        id: UUID = UUID(),
        category: Category,
        severity: Severity,
        title: String,
        message: String,
        metadata: String? = nil,
        isRead: Bool = false,
        isDismissed: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.message = message
        self.metadata = metadata
        self.isRead = isRead
        self.isDismissed = isDismissed
        self.createdAt = createdAt
    }
}

// MARK: - Persistence

extension AppNotification: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "appNotification"
}
