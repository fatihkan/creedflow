import Foundation
import GRDB

// MARK: - Backend Type

/// Identifies which CLI backend runs a task.
package enum CLIBackendType: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case claude
    case codex
    case gemini
    case ollama
    case lmstudio
    case llamacpp
    case mlx
}

// MARK: - Output Events

/// Backend-neutral output event emitted during task execution.
enum CLIOutputEvent: Sendable {
    /// Text output from the CLI
    case text(String)
    /// Tool use notification (Claude only)
    case toolUse(name: String)
    /// Session/model info (Claude only)
    case system(sessionId: String?, model: String?)
    /// Final result with optional cost/token info
    case result(CLIResult)
    /// Error output
    case error(String)
}

/// Final result from a CLI execution.
struct CLIResult: Sendable {
    let output: String?
    let isError: Bool
    let sessionId: String?
    let model: String?
    let costUSD: Double?
    let durationMs: Int?
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - Task Input

/// Backend-neutral input for a CLI task.
struct CLITaskInput: Sendable {
    let prompt: String
    let systemPrompt: String?
    let workingDirectory: String
    let allowedTools: [String]?
    let maxBudgetUSD: Double?
    let timeoutSeconds: Int
    let mcpConfigPath: String?
    let jsonSchema: String?
}

// MARK: - Backend Protocol

/// Protocol for any CLI backend that can execute agent tasks.
protocol CLIBackend: Actor {
    nonisolated var backendType: CLIBackendType { get }

    /// Whether this backend's CLI is installed and available.
    var isAvailable: Bool { get async }

    /// Execute a task and return a stream of output events.
    func execute(_ input: CLITaskInput) async -> (id: UUID, stream: AsyncThrowingStream<CLIOutputEvent, Error>)

    /// Cancel a running task by its process ID.
    func cancel(_ processId: UUID) async

    /// Cancel all running tasks.
    func cancelAll() async

    /// Number of currently active processes.
    func activeCount() -> Int
}

// MARK: - Backend Preferences

/// Declares which backends an agent can run on.
struct BackendPreferences: Sendable {
    /// Ordered list of preferred backends. First available is chosen.
    let preferred: [CLIBackendType]
    /// If true, task requires Claude-specific features (MCP, tools, JSON schema).
    let requiresClaudeFeatures: Bool

    static let `default` = BackendPreferences(
        preferred: [.claude, .codex, .gemini],
        requiresClaudeFeatures: false
    )

    static let claudeOnly = BackendPreferences(
        preferred: [.claude],
        requiresClaudeFeatures: true
    )

    static let anyBackend = BackendPreferences(
        preferred: [.claude, .codex, .gemini],
        requiresClaudeFeatures: false
    )

    /// Prefers Claude (for MCP support) but falls back to other backends if unavailable
    static let claudePreferred = BackendPreferences(
        preferred: [.claude, .codex, .gemini],
        requiresClaudeFeatures: false
    )
}
