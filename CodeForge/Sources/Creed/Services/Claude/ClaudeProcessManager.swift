import Foundation

/// Actor that manages spawning and tracking Claude CLI processes.
/// Each agent invocation gets its own `Process` with piped stdout/stderr.
actor ClaudeProcessManager {
    /// Path to the `claude` CLI executable
    private var claudePath: String
    private var activeProcesses: [UUID: Process] = [:]

    init(claudePath: String = "/usr/local/bin/claude") {
        self.claudePath = claudePath
    }

    func setClaudePath(_ path: String) {
        self.claudePath = path
    }

    /// Spawn a Claude CLI process and return a stream of events.
    /// The process is tracked by a UUID and can be cancelled.
    func run(_ invocation: ClaudeInvocation) -> (id: UUID, stream: AsyncThrowingStream<ClaudeStreamEvent, Error>) {
        let processId = UUID()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = invocation.buildArguments()
        process.currentDirectoryURL = URL(fileURLWithPath: invocation.workingDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        // Clean environment: remove CLAUDECODE to prevent nested session detection
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE")
        env.removeValue(forKey: "CLAUDE_CODE_SESSION")
        process.environment = env

        activeProcesses[processId] = process

        // Launch the process BEFORE creating the stream so no early output is lost
        do {
            try process.run()
        } catch {
            activeProcesses.removeValue(forKey: processId)
            return (processId, AsyncThrowingStream { $0.finish(throwing: error) })
        }

        let stream = AsyncThrowingStream<ClaudeStreamEvent, Error> { continuation in
            // Read stdout in a background task
            let readTask = Task.detached { [stdoutPipe, stderrPipe] in
                var parser = ClaudeStreamParser()
                let handle = stdoutPipe.fileHandleForReading

                // Read stderr for error reporting
                var stderrData = Data()
                let stderrHandle = stderrPipe.fileHandleForReading
                let stderrTask = Task.detached {
                    var collected = Data()
                    while true {
                        let chunk = stderrHandle.availableData
                        if chunk.isEmpty { break }
                        collected.append(chunk)
                    }
                    return collected
                }

                // Read stdout chunks and parse NDJSON
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break } // EOF
                    let events = parser.feed(data)
                    for event in events {
                        continuation.yield(event)
                    }
                }

                // Flush remaining buffer
                if let finalEvent = parser.flush() {
                    continuation.yield(finalEvent)
                }

                stderrData = await stderrTask.value

                // Wait for process to finish
                process.waitUntilExit()

                let exitCode = process.terminationStatus
                if exitCode != 0 {
                    let errorOutput = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                    if errorOutput.contains("auth") || errorOutput.contains("login") {
                        continuation.finish(throwing: ClaudeError.authenticationRequired(errorOutput))
                    } else {
                        continuation.finish(throwing: ClaudeError.processExitedWithError(
                            code: Int(exitCode),
                            stderr: errorOutput
                        ))
                    }
                } else {
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                readTask.cancel()
                if process.isRunning {
                    process.interrupt()
                }
            }
        }

        return (processId, stream)
    }

    /// Cancel a running process. Sends SIGINT first, then SIGTERM after a delay.
    func cancel(_ processId: UUID) async {
        guard let process = activeProcesses[processId], process.isRunning else {
            activeProcesses.removeValue(forKey: processId)
            return
        }

        // Graceful interrupt first
        process.interrupt()

        // Wait up to 5 seconds for graceful shutdown
        try? await Task.sleep(for: .seconds(5))

        if process.isRunning {
            process.terminate()
        }

        activeProcesses.removeValue(forKey: processId)
    }

    /// Get count of active processes
    func activeCount() -> Int {
        // Clean up finished processes
        activeProcesses = activeProcesses.filter { $0.value.isRunning }
        return activeProcesses.count
    }

    /// Cancel all running processes with graceful shutdown
    func cancelAll() async {
        let processesToKill = activeProcesses
        activeProcesses.removeAll()

        for (_, process) in processesToKill where process.isRunning {
            process.interrupt()
        }

        // Wait for graceful shutdown
        try? await Task.sleep(for: .seconds(3))

        // Force kill any that didn't exit
        for (_, process) in processesToKill where process.isRunning {
            process.terminate()
        }
    }
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case processExitedWithError(code: Int, stderr: String)
    case authenticationRequired(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .processExitedWithError(let code, let stderr):
            return "Claude CLI exited with code \(code): \(stderr)"
        case .authenticationRequired(let detail):
            return "Authentication required. Run `claude auth` in terminal. Detail: \(detail)"
        case .timeout:
            return "Agent task timed out"
        case .cancelled:
            return "Agent task was cancelled"
        }
    }
}
