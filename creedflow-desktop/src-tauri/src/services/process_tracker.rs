use std::collections::HashSet;
use std::sync::Mutex;

/// Global singleton tracking all spawned CLI child processes.
/// On app exit, all children receive termination signals — no orphans.
pub static PROCESS_TRACKER: ProcessTracker = ProcessTracker::new();

pub struct ProcessTracker {
    pids: Mutex<HashSet<u32>>,
}

impl ProcessTracker {
    const fn new() -> Self {
        Self {
            pids: Mutex::new(HashSet::new()),
        }
    }

    pub fn track(&self, pid: u32) {
        if pid == 0 { return; }
        self.pids.lock().unwrap().insert(pid);
    }

    pub fn untrack(&self, pid: u32) {
        self.pids.lock().unwrap().remove(&pid);
    }

    pub fn terminate_all(&self) {
        let pids: Vec<u32> = self.pids.lock().unwrap().drain().collect();
        for pid in pids {
            terminate_process(pid);
        }
    }
}

// Const Mutex::new is unstable — use lazy_static alternative
// Actually in Rust 1.63+ Mutex::new is const, so this works.

#[cfg(unix)]
pub fn terminate_process(pid: u32) {
    unsafe {
        libc::kill(pid as i32, libc::SIGTERM);
    }
}

#[cfg(windows)]
pub fn terminate_process(pid: u32) {
    use windows::Win32::System::Threading::{OpenProcess, TerminateProcess, PROCESS_TERMINATE};
    use windows::Win32::Foundation::CloseHandle;
    unsafe {
        if let Ok(handle) = OpenProcess(PROCESS_TERMINATE, false, pid) {
            let _ = TerminateProcess(handle, 1);
            let _ = CloseHandle(handle);
        }
    }
}

#[cfg(not(any(unix, windows)))]
pub fn terminate_process(_pid: u32) {
    log::warn!("Process termination not supported on this platform");
}
