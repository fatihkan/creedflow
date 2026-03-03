use crate::services::health::RateLimitDetector;

/// Retry policy for failed tasks.
/// Default: max 3 retries.
#[derive(Clone, Copy)]
pub struct RetryPolicy {
    pub max_retries: i32,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self { max_retries: 3 }
    }
}

impl RetryPolicy {
    pub fn should_retry(&self, retry_count: i32) -> bool {
        retry_count < self.max_retries
    }

    /// Check if an error message indicates a rate limit.
    pub fn is_rate_limited(error: &str) -> bool {
        RateLimitDetector::detect(error).is_some()
    }

    /// Get rate-limit backoff interval in seconds.
    pub fn rate_limit_backoff(retry_count: i32) -> u64 {
        RateLimitDetector::backoff_interval(retry_count)
    }
}
