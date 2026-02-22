import Foundation

/// Telegram bot integration for notifications and commands.
/// Uses direct HTTP API calls (no external dependency needed for basic functionality).
@Observable
final class TelegramBotService {
    private var botToken: String?
    private var defaultChatId: Int64?
    private(set) var isConnected = false
    private var pollingTask: Task<Void, Never>?

    private let session = URLSession.shared
    private let baseURL = "https://api.telegram.org"

    func configure(token: String, chatId: Int64?) {
        self.botToken = token
        self.defaultChatId = chatId
    }

    /// Send a text message to a chat
    func sendMessage(_ text: String, chatId: Int64? = nil) async throws {
        guard let token = botToken else { return }
        guard let targetChat = chatId ?? defaultChatId else { return }

        let url = URL(string: "\(baseURL)/bot\(token)/sendMessage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "chat_id": targetChat,
            "text": text,
            "parse_mode": "Markdown"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw TelegramError.sendFailed
        }
    }

    /// Send task completion notification
    func notifyTaskCompleted(task: AgentTask, project: Project) async {
        let message = """
            ✅ *Task Completed*
            Project: \(project.name)
            Task: \(task.title)
            Agent: \(task.agentType.rawValue)
            Duration: \(task.durationMs.map { "\($0 / 1000)s" } ?? "N/A")
            Cost: \(task.costUSD.map { String(format: "$%.4f", $0) } ?? "N/A")
            """
        try? await sendMessage(message, chatId: project.telegramChatId)
    }

    /// Send task failure notification
    func notifyTaskFailed(task: AgentTask, project: Project) async {
        let message = """
            ❌ *Task Failed*
            Project: \(project.name)
            Task: \(task.title)
            Error: \(task.errorMessage ?? "Unknown")
            Retries: \(task.retryCount)/\(task.maxRetries)
            """
        try? await sendMessage(message, chatId: project.telegramChatId)
    }

    /// Send review notification
    func notifyReviewCompleted(review: Review, task: AgentTask, project: Project) async {
        let emoji = review.verdict == .pass ? "✅" : review.verdict == .needsRevision ? "⚠️" : "❌"
        let message = """
            \(emoji) *Code Review*
            Project: \(project.name)
            Task: \(task.title)
            Score: \(String(format: "%.1f", review.score))/10
            Verdict: \(review.verdict.rawValue.uppercased())
            Summary: \(review.summary)
            """
        try? await sendMessage(message, chatId: project.telegramChatId)
    }

    /// Start polling for incoming commands
    func startPolling(handler: @escaping (TelegramCommand) async -> Void) {
        guard botToken != nil else { return }
        isConnected = true

        pollingTask = Task { [weak self] in
            var offset: Int64 = 0
            while !Task.isCancelled {
                guard let self else { break }
                if let updates = try? await self.getUpdates(offset: offset) {
                    for update in updates {
                        offset = max(offset, update.updateId + 1)
                        if let command = self.parseCommand(from: update) {
                            await handler(command)
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isConnected = false
    }

    // MARK: - Private

    private func getUpdates(offset: Int64) async throws -> [TelegramUpdate] {
        guard let token = botToken else { return [] }
        let url = URL(string: "\(baseURL)/bot\(token)/getUpdates?offset=\(offset)&timeout=10")!
        let (data, _) = try await session.data(from: url)

        struct Response: Decodable {
            let ok: Bool
            let result: [TelegramUpdate]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.result
    }

    private func parseCommand(from update: TelegramUpdate) -> TelegramCommand? {
        guard let text = update.message?.text, text.hasPrefix("/") else { return nil }
        let parts = text.split(separator: " ", maxSplits: 1)
        let command = String(parts[0].dropFirst()) // remove "/"
        let argument = parts.count > 1 ? String(parts[1]) : nil
        let chatId = update.message?.chat.id ?? 0
        return TelegramCommand(command: command, argument: argument, chatId: chatId)
    }
}

// MARK: - Types

struct TelegramUpdate: Decodable {
    let updateId: Int64
    let message: TelegramMessage?

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
    }
}

struct TelegramMessage: Decodable {
    let text: String?
    let chat: TelegramChat
}

struct TelegramChat: Decodable {
    let id: Int64
}

struct TelegramCommand {
    let command: String  // "new", "status", "tasks", "approve", "deploy"
    let argument: String?
    let chatId: Int64
}

enum TelegramError: LocalizedError {
    case sendFailed
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .sendFailed: return "Failed to send Telegram message"
        case .notConfigured: return "Telegram bot token not configured"
        }
    }
}
