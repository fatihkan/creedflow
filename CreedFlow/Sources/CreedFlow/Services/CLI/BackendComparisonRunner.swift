import Foundation
import os

private let logger = Logger(subsystem: "com.creedflow", category: "BackendComparison")

/// Result of running a prompt against a single backend.
struct BackendComparisonResult: Identifiable, Sendable {
    let id = UUID()
    let backendType: CLIBackendType
    let output: String
    let durationMs: Int
    let error: String?
}

/// Fans out the same prompt to multiple backends concurrently and collects results.
@Observable
package class BackendComparisonRunner {
    private let backendRouter: BackendRouter
    package private(set) var isRunning = false
    package private(set) var results: [BackendComparisonResult] = []

    package init(backendRouter: BackendRouter) {
        self.backendRouter = backendRouter
    }

    /// Run the given prompt against all specified backend types concurrently.
    package func compare(prompt: String, backends backendTypes: [CLIBackendType]) async {
        isRunning = true
        results = []

        let collected = await withTaskGroup(of: BackendComparisonResult.self, returning: [BackendComparisonResult].self) { group in
            for type in backendTypes {
                group.addTask { [backendRouter] in
                    let start = Date()
                    guard let backend = await backendRouter.backend(for: type) else {
                        return BackendComparisonResult(
                            backendType: type,
                            output: "",
                            durationMs: 0,
                            error: "\(type.displayName) is not available"
                        )
                    }

                    let input = CLITaskInput(
                        prompt: prompt,
                        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
                        timeoutSeconds: 120
                    )

                    var outputLines: [String] = []
                    var resultError: String?

                    let (_, stream) = await backend.execute(input)
                    do {
                        for try await event in stream {
                            switch event {
                            case .text(let text):
                                outputLines.append(text)
                            case .result(let result):
                                outputLines.append(result.output ?? "")
                            case .toolUse, .system:
                                break
                            }
                        }
                    } catch {
                        resultError = error.localizedDescription
                    }

                    let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                    return BackendComparisonResult(
                        backendType: type,
                        output: outputLines.joined(separator: "\n"),
                        durationMs: elapsed,
                        error: resultError
                    )
                }
            }

            var results: [BackendComparisonResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        results = collected.sorted { $0.backendType.rawValue < $1.backendType.rawValue }
        isRunning = false
        logger.info("Backend comparison completed: \(collected.count) backends")
    }
}
