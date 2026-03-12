import Foundation

/// Slack Incoming Webhook integration for notifications.
/// Simpler than Telegram — single webhook URL, no polling needed.
@Observable
final class SlackNotificationService {
    private var webhookUrl: String?
    private let session = URLSession.shared

    func configure(webhookUrl: String) {
        self.webhookUrl = webhookUrl
    }

    /// Send a text message to the configured Slack webhook.
    func sendMessage(_ text: String) async throws {
        guard let urlString = webhookUrl, !urlString.isEmpty else {
            throw SlackError.notConfigured
        }
        guard let url = URL(string: urlString) else {
            throw SlackError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw SlackError.sendFailed
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
        try? await sendMessage(message)
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
        try? await sendMessage(message)
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
        try? await sendMessage(message)
    }
}

// MARK: - Types

enum SlackError: LocalizedError {
    case sendFailed
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .sendFailed: return "Failed to send Slack message"
        case .notConfigured: return "Slack webhook URL not configured"
        }
    }
}
