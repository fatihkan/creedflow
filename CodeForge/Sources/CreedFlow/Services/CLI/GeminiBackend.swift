import Foundation

/// CLIBackend for Google's Gemini CLI.
/// Spawns `gemini -p "<prompt>"` and collects plain text output.
actor GeminiBackend: CLIBackend {
    nonisolated let backendType = CLIBackendType.gemini

    private var cliPath: String
    private var activeProcesses: [UUID: Process] = [:]

    init(cliPath: String? = nil) {
        self.cliPath = cliPath
            ?? UserDefaults.standard.string(forKey: "geminiPath").flatMap({ $0.isEmpty ? nil : $0 })
            ?? Self.findCLI()
    }

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: cliPath)
    }

    func execute(_ input: CLITaskInput) async -> (id: UUID, stream: AsyncThrowingStream<CLIOutputEvent, Error>) {
        let processId = UUID()

        // For non-Claude backends, prepend system prompt into the main prompt
        var fullPrompt = input.prompt
        if let sys = input.systemPrompt, !sys.isEmpty {
            fullPrompt = "System instructions:\n\(sys)\n\n---\n\nTask:\n\(input.prompt)"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["-p", fullPrompt]
        process.currentDirectoryURL = URL(fileURLWithPath: input.workingDirectory)
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        activeProcesses[processId] = process

        do {
            try process.run()
        } catch {
            activeProcesses.removeValue(forKey: processId)
            return (processId, AsyncThrowingStream { $0.finish(throwing: error) })
        }

        let startTime = Date()

        let stream = AsyncThrowingStream<CLIOutputEvent, Error> { continuation in
            let readTask = Task.detached { [stdoutPipe, stderrPipe] in
                let handle = stdoutPipe.fileHandleForReading
                var collectedOutput = ""

                // Read stderr in background
                let stderrTask = Task.detached {
                    var data = Data()
                    while true {
                        let chunk = stderrPipe.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        data.append(chunk)
                    }
                    return data
                }

                // Stream stdout chunks
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    if let text = String(data: data, encoding: .utf8) {
                        collectedOutput += text
                        continuation.yield(.text(text))
                    }
                }

                let stderrData = await stderrTask.value
                process.waitUntilExit()

                let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                let exitCode = process.terminationStatus

                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

                if exitCode != 0 {
                    let errorOutput = stderrText.isEmpty ? "Unknown error" : stderrText
                    continuation.yield(.error(errorOutput))
                    let result = CLIResult(
                        output: collectedOutput.isEmpty ? errorOutput : collectedOutput,
                        isError: true,
                        sessionId: nil,
                        model: "gemini",
                        costUSD: nil,
                        durationMs: elapsed,
                        inputTokens: 0,
                        outputTokens: 0
                    )
                    continuation.yield(.result(result))
                    continuation.finish()
                } else {
                    // Fallback to stderr when stdout is empty (some CLIs write output to stderr)
                    let output = collectedOutput.isEmpty ? (stderrText.isEmpty ? nil : stderrText) : collectedOutput
                    let result = CLIResult(
                        output: output,
                        isError: false,
                        sessionId: nil,
                        model: "gemini",
                        costUSD: nil,
                        durationMs: elapsed,
                        inputTokens: 0,
                        outputTokens: 0
                    )
                    continuation.yield(.result(result))
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

    func cancel(_ processId: UUID) async {
        guard let process = activeProcesses[processId], process.isRunning else {
            activeProcesses.removeValue(forKey: processId)
            return
        }
        process.interrupt()
        try? await Task.sleep(for: .seconds(5))
        if process.isRunning { process.terminate() }
        activeProcesses.removeValue(forKey: processId)
    }

    func cancelAll() async {
        let processes = activeProcesses
        activeProcesses.removeAll()
        for (_, process) in processes where process.isRunning {
            process.interrupt()
        }
        try? await Task.sleep(for: .seconds(3))
        for (_, process) in processes where process.isRunning {
            process.terminate()
        }
    }

    func activeCount() -> Int {
        activeProcesses = activeProcesses.filter { $0.value.isRunning }
        return activeProcesses.count
    }

    // MARK: - Path Resolution

    private static func findCLI() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/gemini",
            "/usr/local/bin/gemini",
            "/opt/homebrew/bin/gemini",
            "\(home)/.npm-global/bin/gemini",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return candidates[0]
    }
}
