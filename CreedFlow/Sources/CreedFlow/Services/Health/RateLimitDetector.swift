import Foundation

/// Error thrown when a rate limit is detected in CLI output.
struct RateLimitError: Error, LocalizedError {
    let backendType: CLIBackendType
    let rawSignal: String

    var errorDescription: String? {
        "Rate limited by \(backendType.displayName): \(rawSignal)"
    }
}

/// Detects rate-limit signals in CLI output and computes exponential backoff intervals.
struct RateLimitDetector: Sendable {
    /// Patterns that indicate a rate limit in CLI stderr/stdout.
    static let patterns: [String] = [
        "429",
        "rate limit",
        "rate_limit",
        "too many requests",
        "RESOURCE_EXHAUSTED",
        "quota exceeded",
        "throttled",
        "overloaded",
    ]

    /// Check if an error message contains a rate-limit signal.
    /// Returns the matched pattern or nil.
    static func detect(in text: String) -> String? {
        let lower = text.lowercased()
        for pattern in patterns {
            if lower.contains(pattern.lowercased()) {
                return pattern
            }
        }
        return nil
    }

    /// Exponential backoff for rate limits: 60s base, 2x growth, max 600s.
    static func backoffInterval(retryCount: Int) -> TimeInterval {
        let base: TimeInterval = 60
        let multiplier = pow(2.0, Double(retryCount))
        return min(base * multiplier, 600)
    }
}
