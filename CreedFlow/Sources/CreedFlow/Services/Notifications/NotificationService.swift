import Foundation
import GRDB

/// Central notification bus — persists to SQLite, buffers toasts in memory.
/// All health monitors and engine events funnel through `emit()`.
actor NotificationService {
    private let dbQueue: DatabaseQueue
    private var toastBuffer: [AppNotification] = []
    private let maxToasts = 5
    private let maxPanelItems = 50
    private let pruneAfterDays = 7

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Emit a new notification — persists to DB and adds to toast buffer.
    func emit(
        category: AppNotification.Category,
        severity: AppNotification.Severity,
        title: String,
        message: String,
        metadata: String? = nil
    ) {
        let notification = AppNotification(
            category: category,
            severity: severity,
            title: title,
            message: message,
            metadata: metadata
        )

        // Persist to DB
        try? dbQueue.write { db in
            var n = notification
            try n.insert(db)
        }

        // Add to toast buffer (drop oldest if full)
        toastBuffer.append(notification)
        if toastBuffer.count > maxToasts {
            toastBuffer.removeFirst(toastBuffer.count - maxToasts)
        }
    }

    /// Drain pending toasts for display. Returns and clears the buffer.
    func drainToasts() -> [AppNotification] {
        let pending = toastBuffer
        toastBuffer.removeAll()
        return pending
    }

    /// Mark a notification as read.
    func markRead(_ id: UUID) {
        try? dbQueue.write { db in
            guard var n = try AppNotification.fetchOne(db, id: id) else { return }
            n.isRead = true
            try n.update(db)
        }
    }

    /// Mark all unread notifications as read.
    func markAllRead() {
        try? dbQueue.write { db in
            try db.execute(
                sql: "UPDATE appNotification SET isRead = 1 WHERE isRead = 0"
            )
        }
    }

    /// Dismiss a notification (hides from panel).
    func dismiss(_ id: UUID) {
        try? dbQueue.write { db in
            guard var n = try AppNotification.fetchOne(db, id: id) else { return }
            n.isDismissed = true
            try n.update(db)
        }
    }

    /// Remove notifications older than `pruneAfterDays`.
    func pruneOld() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -pruneAfterDays, to: Date()) ?? Date()
        try? dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM appNotification WHERE createdAt < ?",
                arguments: [cutoff]
            )
            try db.execute(
                sql: "DELETE FROM healthEvent WHERE checkedAt < ?",
                arguments: [cutoff]
            )
        }
    }
}
