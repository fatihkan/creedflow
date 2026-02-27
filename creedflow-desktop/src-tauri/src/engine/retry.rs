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
}
