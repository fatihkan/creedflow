import Foundation

/// Routes agent tasks to the appropriate CLI backend using round-robin
/// load balancing, with MCP-aware routing for agents that need Claude features.
actor BackendRouter {
    private var backends: [CLIBackendType: any CLIBackend] = [:]
    private var roundRobinIndex: Int = 0

    /// Register a backend. Overwrites any existing backend of the same type.
    func register(_ backend: any CLIBackend) {
        backends[backend.backendType] = backend
    }

    /// All registered backends.
    var allBackends: [any CLIBackend] {
        Array(backends.values)
    }

    /// Select the best available backend for the given agent and task.
    ///
    /// Selection logic:
    /// 1. If the agent requires Claude features (MCP, tools, JSON schema) → Claude only
    /// 2. Otherwise, round-robin across the agent's preferred backends that are available
    /// 3. Falls back to Claude if no preferred backend is available
    func selectBackend(agent: any AgentProtocol, task: AgentTask) async -> any CLIBackend {
        let prefs = agent.backendPreferences

        // If agent requires Claude-specific features, always use Claude
        if prefs.requiresClaudeFeatures {
            if let claude = backends[.claude] {
                return claude
            }
        }

        // Collect available backends from the agent's preference list
        var available: [any CLIBackend] = []
        for type in prefs.preferred {
            if let backend = backends[type], await backend.isAvailable {
                available.append(backend)
            }
        }

        // Fallback to Claude if nothing else is available
        if available.isEmpty {
            if let claude = backends[.claude] {
                return claude
            }
            // Last resort: return whatever we have
            return backends.values.first!
        }

        // Round-robin across available backends
        let index = roundRobinIndex % available.count
        roundRobinIndex += 1
        return available[index]
    }

    /// Get a specific backend by type.
    func backend(for type: CLIBackendType) -> (any CLIBackend)? {
        backends[type]
    }
}
