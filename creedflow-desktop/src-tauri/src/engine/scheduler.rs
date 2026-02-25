use tokio::sync::Semaphore;
use std::sync::Arc;

/// Controls agent concurrency — max N concurrent tasks.
/// Mirrors Swift AgentScheduler using tokio::sync::Semaphore.
pub struct AgentScheduler {
    semaphore: Arc<Semaphore>,
    max_concurrency: usize,
}

impl AgentScheduler {
    pub fn new(max_concurrency: usize) -> Self {
        Self {
            semaphore: Arc::new(Semaphore::new(max_concurrency)),
            max_concurrency,
        }
    }

    /// Try to acquire a slot. Returns None if all slots are in use.
    pub fn try_acquire(&self) -> Option<tokio::sync::OwnedSemaphorePermit> {
        self.semaphore.clone().try_acquire_owned().ok()
    }

    /// Get available slot count.
    pub fn available_slots(&self) -> usize {
        self.semaphore.available_permits()
    }

    /// Get active (in-use) slot count.
    pub fn active_count(&self) -> usize {
        self.max_concurrency - self.semaphore.available_permits()
    }

    pub fn max_concurrency(&self) -> usize {
        self.max_concurrency
    }
}
