import Foundation

/// CLIBackend for LM Studio local LLM.
/// Uses HTTP POST to `localhost:1234/v1/chat/completions` (OpenAI-compatible API).
actor LMStudioBackend: CLIBackend {
    nonisolated let backendType = CLIBackendType.lmstudio

    private var activeTasks: Set<UUID> = []

    var isAvailable: Bool {
        get async {
            // Check if localhost:1234 is reachable with a quick HEAD request
            guard let url = URL(string: "http://localhost:1234/v1/models") else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 2
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    return http.statusCode == 200
                }
                return false
            } catch {
                return false
            }
        }
    }

    private var modelName: String {
        UserDefaults.standard.string(forKey: "lmstudioModel").flatMap({ $0.isEmpty ? nil : $0 })
            ?? "default"
    }

    func execute(_ input: CLITaskInput) async -> (id: UUID, stream: AsyncThrowingStream<CLIOutputEvent, Error>) {
        let processId = UUID()
        let model = modelName
        let startTime = Date()

        guard let url = URL(string: "http://localhost:1234/v1/chat/completions") else {
            return (processId, AsyncThrowingStream { $0.finish(throwing: NSError(domain: "LMStudioBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])) })
        }

        // Build messages array
        var messages: [[String: String]] = []
        if let sys = input.systemPrompt, !sys.isEmpty {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(["role": "user", "content": input.prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 4096,
            "stream": false,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = TimeInterval(input.timeoutSeconds)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return (processId, AsyncThrowingStream { $0.finish(throwing: error) })
        }

        activeTasks.insert(processId)
        let capturedRequest = request

        let stream = AsyncThrowingStream<CLIOutputEvent, Error> { continuation in
            let asyncTask = Task { [weak self] in
                defer {
                    Task { await self?.removeActiveTask(processId) }
                }

                do {
                    let (data, _) = try await URLSession.shared.data(for: capturedRequest)
                    let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)

                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let first = choices.first,
                          let message = first["message"] as? [String: Any],
                          let content = message["content"] as? String else {
                        let raw = String(data: data, encoding: .utf8) ?? "Unknown response"
                        continuation.yield(.error("Failed to parse response: \(raw)"))
                        let result = CLIResult(
                            output: raw, isError: true, sessionId: nil,
                            model: "lmstudio:\(model)", costUSD: nil,
                            durationMs: elapsed, inputTokens: 0, outputTokens: 0
                        )
                        continuation.yield(.result(result))
                        continuation.finish()
                        return
                    }

                    let usage = json["usage"] as? [String: Any]
                    let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
                    let outputTokens = usage?["completion_tokens"] as? Int ?? 0

                    continuation.yield(.text(content))
                    let result = CLIResult(
                        output: content, isError: false, sessionId: nil,
                        model: "lmstudio:\(model)", costUSD: nil,
                        durationMs: elapsed, inputTokens: inputTokens, outputTokens: outputTokens
                    )
                    continuation.yield(.result(result))
                    continuation.finish()
                } catch {
                    let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                    continuation.yield(.error(error.localizedDescription))
                    let result = CLIResult(
                        output: error.localizedDescription, isError: true, sessionId: nil,
                        model: "lmstudio:\(model)", costUSD: nil,
                        durationMs: elapsed, inputTokens: 0, outputTokens: 0
                    )
                    continuation.yield(.result(result))
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                asyncTask.cancel()
            }
        }

        return (processId, stream)
    }

    private func removeActiveTask(_ id: UUID) {
        activeTasks.remove(id)
    }

    func cancel(_ processId: UUID) async {
        activeTasks.remove(processId)
    }

    func cancelAll() async {
        activeTasks.removeAll()
    }

    func activeCount() -> Int {
        activeTasks.count
    }
}
