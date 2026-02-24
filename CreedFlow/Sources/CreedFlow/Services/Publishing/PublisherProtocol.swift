import Foundation

/// Protocol for publishing content to external platforms.
protocol PublisherProtocol: Sendable {
    var channelType: PublishingChannel.ChannelType { get }

    /// Publish exported content to the platform.
    func publish(content: ExportedContent, options: PublishOptions) async throws -> PublicationResult

    /// Validate that the provided credentials are correct.
    func validateCredentials(_ credentials: [String: String]) async throws -> Bool
}

/// Content ready for publishing.
struct ExportedContent: Sendable {
    let title: String
    let body: String
    let format: Publication.ExportFormat
}

/// Options for a publish action.
struct PublishOptions: Sendable {
    let title: String
    let tags: [String]
    let scheduledAt: Date?
    let isDraft: Bool
    let credentials: [String: String]

    init(title: String, tags: [String] = [], scheduledAt: Date? = nil, isDraft: Bool = false, credentials: [String: String] = [:]) {
        self.title = title
        self.tags = tags
        self.scheduledAt = scheduledAt
        self.isDraft = isDraft
        self.credentials = credentials
    }
}

/// Result from a successful publish.
struct PublicationResult: Sendable {
    let externalId: String
    let url: String
    let publishedAt: Date
}

/// Errors from publishing operations.
enum PublishingError: Error, LocalizedError {
    case missingCredential(String)
    case apiError(String)
    case unsupportedFormat(String)
    case channelNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let key): return "Missing credential: \(key)"
        case .apiError(let msg): return "API error: \(msg)"
        case .unsupportedFormat(let fmt): return "Unsupported format: \(fmt)"
        case .channelNotFound(let id): return "Channel not found: \(id)"
        }
    }
}
