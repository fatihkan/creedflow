import Foundation
import GRDB

/// Observable view model that bridges NotificationService (actor) to SwiftUI.
/// Uses GRDB ValueObservation for unread count and recent notifications,
/// and polls the actor for pending toasts every 2 seconds.
@Observable
final class NotificationViewModel {
    private let dbQueue: DatabaseQueue
    private let service: NotificationService
    private var observationTask: Task<Void, Never>?
    private var toastPollTask: Task<Void, Never>?

    private(set) var unreadCount: Int = 0
    private(set) var recentNotifications: [AppNotification] = []
    private(set) var pendingToasts: [AppNotification] = []

    init(dbQueue: DatabaseQueue, service: NotificationService) {
        self.dbQueue = dbQueue
        self.service = service
    }

    /// Start observing DB changes and polling toasts. Call from `.task {}`.
    func startObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            guard let self else { return }
            await self.observeNotifications()
        }
        toastPollTask?.cancel()
        toastPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let toasts = await self.service.drainToasts()
                if !toasts.isEmpty {
                    await MainActor.run {
                        self.pendingToasts.append(contentsOf: toasts)
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Stop all observation.
    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        toastPollTask?.cancel()
        toastPollTask = nil
    }

    /// Remove a toast from the pending list (after display/dismiss).
    func removeToast(_ id: UUID) {
        pendingToasts.removeAll { $0.id == id }
    }

    func markRead(_ id: UUID) {
        Task { await service.markRead(id) }
    }

    func markAllRead() {
        Task { await service.markAllRead() }
    }

    func dismiss(_ id: UUID) {
        Task { await service.dismiss(id) }
    }

    // MARK: - Private

    private func observeNotifications() async {
        let observation = ValueObservation.tracking { db -> (Int, [AppNotification]) in
            let unread = try AppNotification
                .filter(Column("isRead") == false)
                .filter(Column("isDismissed") == false)
                .fetchCount(db)
            let recent = try AppNotification
                .filter(Column("isDismissed") == false)
                .order(Column("createdAt").desc)
                .limit(50)
                .fetchAll(db)
            return (unread, recent)
        }
        do {
            for try await (count, items) in observation.values(in: dbQueue) {
                unreadCount = count
                recentNotifications = items
            }
        } catch {
            // Observation stream ended — stale data but non-fatal
        }
    }
}
