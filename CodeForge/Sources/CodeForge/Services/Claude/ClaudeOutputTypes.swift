import Foundation

/// Events emitted by Claude CLI's `--output-format stream-json` (NDJSON).
/// Each line of output is one of these event types.
enum ClaudeStreamEvent: Sendable {
    case system(SystemEvent)
    case assistant(AssistantEvent)
    case result(ResultEvent)
    case unknown(String)

    struct SystemEvent: Decodable, Sendable {
        let sessionId: String
        let tools: [String]?
        let model: String?
    }

    struct ContentBlock: Decodable, Sendable {
        let type: String        // "text" or "tool_use"
        let text: String?
        let id: String?         // tool use id
        let name: String?       // tool name
        let input: String?      // tool input JSON as string
    }

    struct AssistantEvent: Decodable, Sendable {
        let message: AssistantMessage
        let sessionId: String
    }

    struct AssistantMessage: Decodable, Sendable {
        let role: String
        let content: [ContentBlock]
    }

    struct ResultEvent: Decodable, Sendable {
        let sessionId: String
        let result: String?
        let cost: CostInfo?
        let durationMs: Int?
        let isError: Bool?
        let totalCostUsd: Double?

        struct CostInfo: Decodable, Sendable {
            let inputTokens: Int?
            let outputTokens: Int?
            let totalUsd: Double?
        }
    }
}

/// Intermediate raw JSON type for decoding NDJSON events
struct RawClaudeEvent: Decodable {
    let type: String
    let sessionId: String?
    let tools: [String]?
    let model: String?
    let message: ClaudeStreamEvent.AssistantMessage?
    let result: String?
    let cost: ClaudeStreamEvent.ResultEvent.CostInfo?
    let durationMs: Int?
    let isError: Bool?
    let totalCostUsd: Double?
}

extension ClaudeStreamEvent {
    /// Parse a single NDJSON line into a stream event
    static func parse(from jsonString: String) -> ClaudeStreamEvent? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let raw = try? decoder.decode(RawClaudeEvent.self, from: data) else {
            return .unknown(jsonString)
        }

        switch raw.type {
        case "system":
            return .system(SystemEvent(
                sessionId: raw.sessionId ?? "",
                tools: raw.tools,
                model: raw.model
            ))
        case "assistant":
            guard let message = raw.message else { return .unknown(jsonString) }
            return .assistant(AssistantEvent(
                message: message,
                sessionId: raw.sessionId ?? ""
            ))
        case "result":
            return .result(ResultEvent(
                sessionId: raw.sessionId ?? "",
                result: raw.result,
                cost: raw.cost,
                durationMs: raw.durationMs,
                isError: raw.isError,
                totalCostUsd: raw.totalCostUsd
            ))
        default:
            return .unknown(jsonString)
        }
    }

    /// Extract text content from an assistant event
    var textContent: String? {
        guard case .assistant(let event) = self else { return nil }
        let texts = event.message.content.compactMap(\.text)
        return texts.isEmpty ? nil : texts.joined()
    }
}

/// Configuration for a Claude CLI invocation
struct ClaudeInvocation: Sendable {
    let prompt: String
    let workingDirectory: String
    let systemPrompt: String?
    let outputFormat: OutputFormat
    let allowedTools: [String]?
    let maxBudgetUSD: Double?
    let jsonSchema: String?
    let resumeSessionId: String?

    enum OutputFormat: String, Sendable {
        case streamJSON = "stream-json"
        case json = "json"
    }

    init(
        prompt: String,
        workingDirectory: String,
        systemPrompt: String? = nil,
        outputFormat: OutputFormat = .streamJSON,
        allowedTools: [String]? = nil,
        maxBudgetUSD: Double? = nil,
        jsonSchema: String? = nil,
        resumeSessionId: String? = nil
    ) {
        self.prompt = prompt
        self.workingDirectory = workingDirectory
        self.systemPrompt = systemPrompt
        self.outputFormat = outputFormat
        self.allowedTools = allowedTools
        self.maxBudgetUSD = maxBudgetUSD
        self.jsonSchema = jsonSchema
        self.resumeSessionId = resumeSessionId
    }

    /// Build the full command-line arguments for `claude`
    func buildArguments() -> [String] {
        var args: [String] = []

        if let sessionId = resumeSessionId {
            args += ["-p", prompt, "--resume", sessionId]
        } else {
            args += ["-p", prompt]
        }

        args += ["--output-format", outputFormat.rawValue]

        if let systemPrompt {
            args += ["--system-prompt", systemPrompt]
        }
        if let tools = allowedTools, !tools.isEmpty {
            args += ["--allowedTools", tools.joined(separator: ",")]
        }
        if let budget = maxBudgetUSD {
            args += ["--max-budget-usd", String(format: "%.2f", budget)]
        }
        if let schema = jsonSchema {
            args += ["--json-schema", schema]
        }

        return args
    }
}
