import Foundation

/// Reads/writes per-agent CLI backend preference overrides from UserDefaults.
///
/// Each agent has a hardcoded default (e.g. Coder → claudeOnly). This store lets
/// users customize the **preference order** while keeping `requiresClaudeFeatures`
/// read-only from the hardcoded default.
///
/// Storage: single UserDefaults key `"agentBackendPreferences"` holding `[String: [String]]`.
final class AgentBackendPreferencesStore: Sendable {
    private static let key = "agentBackendPreferences"

    // MARK: - Hardcoded Defaults

    /// Maps each agent type to its built-in default `BackendPreferences`.
    static let defaults: [AgentTask.AgentType: BackendPreferences] = [
        .analyzer: .anyBackend,
        .coder: .claudeOnly,
        .reviewer: .claudeOnly,
        .tester: .claudeOnly,
        .devops: .default,
        .monitor: .default,
        .contentWriter: .claudePreferred,
        .designer: .claudePreferred,
        .imageGenerator: .claudePreferred,
        .videoEditor: .claudePreferred,
        .publisher: .claudePreferred,
    ]

    // MARK: - Read

    /// Returns the effective `BackendPreferences` for an agent type.
    /// User overrides change the `preferred` list; `requiresClaudeFeatures` always
    /// comes from the hardcoded default.
    func preferences(for agentType: AgentTask.AgentType) -> BackendPreferences {
        let hardcoded = Self.defaults[agentType] ?? .default

        guard let overrides = loadOverrides(),
              let raw = overrides[agentType.rawValue],
              !raw.isEmpty else {
            return hardcoded
        }

        let preferred = raw.compactMap { CLIBackendType(rawValue: $0) }
        guard !preferred.isEmpty else { return hardcoded }

        return BackendPreferences(
            preferred: preferred,
            requiresClaudeFeatures: hardcoded.requiresClaudeFeatures
        )
    }

    /// Whether the user has a custom override for the given agent type.
    func isCustomized(for agentType: AgentTask.AgentType) -> Bool {
        guard let overrides = loadOverrides() else { return false }
        return overrides[agentType.rawValue] != nil
    }

    // MARK: - Write

    /// Save a custom preferred backend order for one agent.
    /// Passing an empty array resets to default.
    func setPreferred(_ backends: [CLIBackendType], for agentType: AgentTask.AgentType) {
        var overrides = loadOverrides() ?? [:]
        if backends.isEmpty {
            overrides.removeValue(forKey: agentType.rawValue)
        } else {
            overrides[agentType.rawValue] = backends.map(\.rawValue)
        }
        saveOverrides(overrides)
    }

    /// Remove the override for a single agent, reverting to its hardcoded default.
    func resetToDefault(for agentType: AgentTask.AgentType) {
        var overrides = loadOverrides() ?? [:]
        overrides.removeValue(forKey: agentType.rawValue)
        saveOverrides(overrides)
    }

    /// Remove all overrides.
    func resetAll() {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    // MARK: - Private

    private func loadOverrides() -> [String: [String]]? {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return nil
        }
        return dict
    }

    private func saveOverrides(_ overrides: [String: [String]]) {
        if overrides.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
