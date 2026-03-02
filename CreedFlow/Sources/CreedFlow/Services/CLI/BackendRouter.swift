import Foundation
import os

private let logger = Logger(subsystem: "com.creedflow", category: "BackendRouter")

/// Routes agent tasks to the appropriate CLI backend using round-robin
/// load balancing, with MCP-aware routing for agents that need Claude features.
///
/// **Hard rules:**
/// - A backend that is disabled in Settings is NEVER selected.
/// - A backend whose CLI binary is missing (`isAvailable == false`) is NEVER selected.
/// - If a preferred backend is unavailable, fall back to any other active backend.
/// - Returns `nil` only when zero backends are enabled and available.
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

    /// All backends that are both enabled in settings AND have their CLI binary available.
    private func allUsableBackends() async -> [any CLIBackend] {
        var usable: [any CLIBackend] = []
        for (type, backend) in backends {
            if isEnabled(type), await backend.isAvailable {
                usable.append(backend)
            }
        }
        return usable
    }

    /// Select the best available backend for the given agent and task.
    /// Returns `nil` only when no backend at all is enabled and available.
    ///
    /// Selection logic:
    /// 1. If the agent prefers Claude (MCP features) → use Claude if active.
    /// 2. Collect enabled+available backends from the agent's preference list.
    /// 3. If none from the preference list, fall back to ANY active backend.
    /// 4. Round-robin across the resulting pool.
    func selectBackend(preferences prefs: BackendPreferences, task: AgentTask) async -> (any CLIBackend)? {

        // If agent prefers Claude for MCP features, try Claude first
        if prefs.requiresClaudeFeatures {
            if let claude = backends[.claude], isEnabled(.claude), await claude.isAvailable {
                return claude
            }
            // Claude not usable — fall through to find any active backend
            logger.info("Agent \(task.agentType.rawValue) prefers Claude but it is unavailable — falling back to other backends")
        }

        // Collect enabled+available backends from the agent's preference list
        var available: [any CLIBackend] = []
        for type in prefs.preferred {
            if let backend = backends[type], isEnabled(type), await backend.isAvailable {
                available.append(backend)
            }
        }

        // If no preferred backend is usable, fall back to ANY active backend
        if available.isEmpty {
            available = await allUsableBackends()
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

    /// Select any usable backend using the given preferences (no task context).
    func selectBackend(preferences prefs: BackendPreferences) async -> (any CLIBackend)? {
        // Try preferred backends first
        for type in prefs.preferred {
            if let backend = backends[type], isEnabled(type), await backend.isAvailable {
                return backend
            }
        }
        // Fall back to any usable backend
        let usable = await allUsableBackends()
        guard !usable.isEmpty else { return nil }
        let index = roundRobinIndex % usable.count
        roundRobinIndex += 1
        return usable[index]
    }

    /// Get a specific backend by type (only if enabled and available).
    func backend(for type: CLIBackendType) async -> (any CLIBackend)? {
        guard let b = backends[type], isEnabled(type), await b.isAvailable else { return nil }
        return b
    }
}
