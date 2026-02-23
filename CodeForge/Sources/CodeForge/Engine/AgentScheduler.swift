import Foundation

/// Controls concurrent agent execution with semaphore-based limiting.
/// Ensures no more than `maxConcurrency` agents run at once,
/// and only one coder agent per project directory.
actor AgentScheduler {
    private let semaphore: AsyncSemaphore
    private var activeProjectCoders: Set<UUID> = [] // project IDs with active coder agents
    private let maxConcurrency: Int

    init(maxConcurrency: Int = 3) {
        self.maxConcurrency = maxConcurrency
        self.semaphore = AsyncSemaphore(value: maxConcurrency)
    }

    /// Acquire a slot for an agent task. Blocks until a slot is available.
    /// Returns false if the task can't be scheduled (e.g., coder conflict).
    func acquire(task: AgentTask) async -> Bool {
        // Check coder serialization: only one coder per project
        if task.agentType == .coder {
            if activeProjectCoders.contains(task.projectId) {
                return false
            }
        }

        await semaphore.wait()

        if task.agentType == .coder {
            activeProjectCoders.insert(task.projectId)
        }

        return true
    }

    /// Try to acquire a slot without blocking. Returns false if no slot available or conflict.
    func tryAcquire(task: AgentTask) async -> Bool {
        if task.agentType == .coder {
            if activeProjectCoders.contains(task.projectId) {
                return false
            }
        }

        guard await semaphore.tryWait() else {
            return false
        }

        if task.agentType == .coder {
            activeProjectCoders.insert(task.projectId)
        }

        return true
    }

    /// Release a slot after task completion
    func release(task: AgentTask) async {
        if task.agentType == .coder {
            activeProjectCoders.remove(task.projectId)
        }
        await semaphore.signal()
    }

    /// Get current stats
    var stats: SchedulerStats {
        get async {
            SchedulerStats(
                availableSlots: await semaphore.availableSlots,
                waitingTasks: await semaphore.waitingCount,
                activeCoderProjects: activeProjectCoders.count,
                maxConcurrency: maxConcurrency
            )
        }
    }

    struct SchedulerStats: Sendable {
        let availableSlots: Int
        let waitingTasks: Int
        let activeCoderProjects: Int
        let maxConcurrency: Int
    }
}
