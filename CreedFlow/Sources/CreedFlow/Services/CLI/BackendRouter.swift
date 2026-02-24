import Foundation
import os

private let logger = Logger(subsystem: "com.creedflow", category: "BackendRouter")

/// Routes agent tasks to the appropriate CLI backend using round-robin
/// load balancing, with MCP-aware routing for agents that need Claude features.
///
/// **Hard rules:**
/// - A backend that is disabled in Settings is NEVER selected.
/// - A backend whose CLI binary is missing (`isAvailable == false`) is NEVER selected.
/// - If no suitable backend exists, `selectBackend` returns `nil` and the task is skipped.
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

    /// Check whether a backend type is enabled in user settings.
    /// Reads `claudeEnabled`, `codexEnabled`, `geminiEnabled` from UserDefaults (default: true).
    nonisolated func isEnabled(_ type: CLIBackendType) -> Bool {
        UserDefaults.standard.object(forKey: "\(type.rawValue)Enabled") as? Bool ?? true
    }

    /// Select the best available backend for the given agent and task.
    /// Returns `nil` when no suitable, enabled, and available backend exists.
    ///
    /// Selection logic:
    /// 1. If the agent requires Claude features → return Claude only if enabled AND available.
    /// 2. Otherwise, round-robin across the agent's preferred backends that are available AND enabled.
    /// 3. Never returns a disabled or unavailable backend.
    func selectBackend(agent: any AgentProtocol, task: AgentTask) async -> (any CLIBackend)? {
        let prefs = agent.backendPreferences

        // If agent requires Claude-specific features, Claude must be enabled + available
        if prefs.requiresClaudeFeatures {
            if let claude = backends[.claude], isEnabled(.claude), await claude.isAvailable {
                return claude
            }
            // Claude required but not usable — no fallback for MCP-dependent agents
            logger.warning("Agent \(task.agentType.rawValue) requires Claude but it is disabled or unavailable — skipping task \(task.id)")
            return nil
        }

        // Collect available AND enabled backends from the agent's preference list
        var available: [any CLIBackend] = []
        for type in prefs.preferred {
            if let backend = backends[type], isEnabled(type), await backend.isAvailable {
                available.append(backend)
            }
        }

        if available.isEmpty {
            logger.warning("No enabled and available backend for agent \(task.agentType.rawValue) — skipping task \(task.id)")
            return nil
        }

        // Round-robin across available backends
        let index = roundRobinIndex % available.count
        roundRobinIndex += 1
        return available[index]
    }

    /// Get a specific backend by type (only if enabled and available).
    func backend(for type: CLIBackendType) async -> (any CLIBackend)? {
        guard let b = backends[type], isEnabled(type), await b.isAvailable else { return nil }
        return b
    }
}
