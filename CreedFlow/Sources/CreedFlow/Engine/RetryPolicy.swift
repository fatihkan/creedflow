import Foundation

/// Retry policy with exponential backoff.
struct RetryPolicy: Sendable {
    let maxRetries: Int
    let backoffIntervals: [TimeInterval]
    let nonRetryableErrors: Set<String>

    static let `default` = RetryPolicy(
        maxRetries: 3,
        backoffIntervals: [5, 30, 120],
        nonRetryableErrors: ["auth", "cancelled", "budget"]
    )

    /// Whether a task should be retried based on its current state
    func shouldRetry(task: AgentTask, error: Error) -> Bool {
        guard task.retryCount < maxRetries else { return false }

        let errorDesc = error.localizedDescription.lowercased()
        for nonRetryable in nonRetryableErrors {
            if errorDesc.contains(nonRetryable) {
                return false
            }
        }

        return true
    }

    /// Get the backoff interval for the given retry attempt
    func backoffInterval(for retryCount: Int) -> TimeInterval {
        guard retryCount < backoffIntervals.count else {
            return backoffIntervals.last ?? 120
        }
        return backoffIntervals[retryCount]
    }

    /// Check if an error is a rate-limit error.
    func isRateLimited(error: Error) -> Bool {
        error is RateLimitError || RateLimitDetector.detect(in: error.localizedDescription) != nil
    }

    /// Get the backoff interval for a rate-limited retry (longer than normal).
    func rateLimitBackoff(retryCount: Int) -> TimeInterval {
        RateLimitDetector.backoffInterval(retryCount: retryCount)
    }
}
