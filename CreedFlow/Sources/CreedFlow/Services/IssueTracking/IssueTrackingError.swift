import Foundation

/// Errors for issue tracking integration.
package enum IssueTrackingError: Error, LocalizedError {
    case invalidCredentials
    case apiError(String)
    case notImplemented(String)
    case configNotFound

    package var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid or missing API credentials"
        case .apiError(let message):
            return "API error: \(message)"
        case .notImplemented(let provider):
            return "\(provider) integration is not yet implemented"
        case .configNotFound:
            return "Issue tracking configuration not found"
        }
    }
}
