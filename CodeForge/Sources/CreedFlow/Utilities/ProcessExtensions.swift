import Foundation

extension Process {
    /// Run a CLI command and return its stdout output as a string.
    /// Throws if the process exits with non-zero status.
    @discardableResult
    static func run(
        _ executablePath: String,
        arguments: [String],
        currentDirectory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        if let dir = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }
        if let env = environment {
            process.environment = env
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""

                if proc.terminationStatus != 0 {
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: ProcessError.failed(
                        exitCode: Int(proc.terminationStatus),
                        output: output,
                        error: errorOutput
                    ))
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum ProcessError: LocalizedError {
    case failed(exitCode: Int, output: String, error: String)

    var errorDescription: String? {
        switch self {
        case .failed(let code, _, let error):
            return "Process exited with code \(code): \(error)"
        }
    }
}
