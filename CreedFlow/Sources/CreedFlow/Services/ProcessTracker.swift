import Foundation

/// Global registry of child processes spawned by CLI backends.
/// Ensures all child processes are terminated when the app exits.
package final class ProcessTracker: @unchecked Sendable {
    package static let shared = ProcessTracker()

    private let lock = NSLock()
    private var processes: Set<Int32> = [] // tracked by PID

    private init() {}

    /// Register a running process for cleanup on app termination.
    package func track(_ process: Process) {
        guard process.isRunning else { return }
        lock.lock()
        processes.insert(process.processIdentifier)
        lock.unlock()
    }

    /// Unregister a process (already exited normally).
    package func untrack(_ process: Process) {
        lock.lock()
        processes.remove(process.processIdentifier)
        lock.unlock()
    }

    /// Terminate all tracked child processes. Called from applicationWillTerminate.
    package func terminateAll() {
        lock.lock()
        for pid in processes {
            kill(pid, SIGTERM)
        }
        processes.removeAll()
        lock.unlock()
    }
}
