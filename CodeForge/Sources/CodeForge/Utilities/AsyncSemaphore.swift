import Foundation

/// Async-aware counting semaphore for limiting concurrent agent execution.
actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.count = value
    }

    /// Wait until a slot is available, then decrement.
    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Release a slot, waking the next waiter if any.
    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            count += 1
        }
    }

    /// Current number of available slots
    var availableSlots: Int { count }

    /// Number of tasks waiting for a slot
    var waitingCount: Int { waiters.count }
}
