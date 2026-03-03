import Foundation
import GRDB
import SwiftUI

// MARK: - Backend Type

/// Identifies which CLI backend runs a task.
package enum CLIBackendType: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case claude
    case codex
    case gemini
    case opencode
    case openclaw
    case ollama
    case lmstudio
    case llamacpp
    case mlx

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .opencode: return "OpenCode"
        case .openclaw: return "OpenClaw"
        case .ollama: return "Ollama"
        case .lmstudio: return "LM Studio"
        case .llamacpp: return "llama.cpp"
        case .mlx: return "MLX"
        }
    }

    var backendColor: Color {
        switch self {
        case .claude: return .purple
        case .codex: return .green
        case .gemini: return .blue
        case .opencode: return .teal
        case .openclaw: return .red
        case .ollama: return .orange
        case .lmstudio: return .cyan
        case .llamacpp: return .pink
        case .mlx: return .mint
        }
    }
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

// MARK: - Chat Attachment

/// A file or image attached to a chat message.
package struct ChatAttachment: Codable, Sendable, Equatable {
    package let path: String      // absolute filesystem path
    package let name: String      // display name (filename)
    package let isImage: Bool     // true=image, false=text file

    package init(path: String, name: String, isImage: Bool) {
        self.path = path
        self.name = name
        self.isImage = isImage
    }
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
    let attachments: [ChatAttachment]

    init(
        prompt: String,
        systemPrompt: String? = nil,
        workingDirectory: String,
        allowedTools: [String]? = nil,
        maxBudgetUSD: Double? = nil,
        timeoutSeconds: Int,
        mcpConfigPath: String? = nil,
        jsonSchema: String? = nil,
        attachments: [ChatAttachment] = []
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.workingDirectory = workingDirectory
        self.allowedTools = allowedTools
        self.maxBudgetUSD = maxBudgetUSD
        self.timeoutSeconds = timeoutSeconds
        self.mcpConfigPath = mcpConfigPath
        self.jsonSchema = jsonSchema
        self.attachments = attachments
    }
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
        preferred: [.claude, .codex, .gemini, .opencode, .openclaw],
        requiresClaudeFeatures: false
    )

    static let claudeOnly = BackendPreferences(
        preferred: [.claude],
        requiresClaudeFeatures: true
    )

    static let anyBackend = BackendPreferences(
        preferred: [.claude, .codex, .gemini, .opencode, .openclaw],
        requiresClaudeFeatures: false
    )

    /// Prefers Claude (for MCP support) but falls back to other backends if unavailable
    static let claudePreferred = BackendPreferences(
        preferred: [.claude, .codex, .gemini, .opencode, .openclaw],
        requiresClaudeFeatures: false
    )
}
