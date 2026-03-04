import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.creedflow", category: "WebhookServer")

/// Lightweight HTTP server using Network.framework (NWListener).
/// Routes: GET /api/status, POST /api/tasks. Optional X-API-Key auth.
@Observable
package class WebhookServer {
    package private(set) var isRunning = false
    private var listener: NWListener?
    private var port: UInt16
    private var apiKey: String?
    private var onCreateTask: ((WebhookTaskRequest) async -> WebhookTaskResponse)?

    package init(port: UInt16 = 8080, apiKey: String? = nil) {
        self.port = port
        self.apiKey = apiKey
    }

    package func configure(port: UInt16, apiKey: String?) {
        self.port = port
        self.apiKey = apiKey
    }

    package func start(onCreateTask: @escaping (WebhookTaskRequest) async -> WebhookTaskResponse) {
        guard !isRunning else { return }
        self.onCreateTask = onCreateTask

        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            logger.error("Failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                logger.info("Webhook server listening on port \(self?.port ?? 0)")
                self?.isRunning = true
            case .failed(let error):
                logger.error("Webhook server failed: \(error)")
                self?.isRunning = false
            case .cancelled:
                self?.isRunning = false
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: .global(qos: .utility))
    }

    package func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        logger.info("Webhook server stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""
            Task {
                let response = await self.routeRequest(request)
                let responseData = Data(response.utf8)
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func routeRequest(_ raw: String) async -> String {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return httpResponse(status: 400, body: #"{"error":"Bad request"}"#)
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: 400, body: #"{"error":"Bad request"}"#)
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // Check API key if configured
        if let apiKey, !apiKey.isEmpty {
            let headerKey = lines.first { $0.lowercased().hasPrefix("x-api-key:") }
                .map { $0.dropFirst("x-api-key:".count).trimmingCharacters(in: .whitespaces) }
            guard headerKey == apiKey else {
                return httpResponse(status: 401, body: #"{"error":"Unauthorized"}"#)
            }
        }

        switch (method, path) {
        case ("GET", "/api/status"):
            return httpResponse(status: 200, body: #"{"status":"ok","version":"1.5.0"}"#)

        case ("POST", "/api/tasks"):
            // Extract body (after blank line)
            let bodyStart = raw.range(of: "\r\n\r\n")?.upperBound ?? raw.endIndex
            let body = String(raw[bodyStart...])

            guard let data = body.data(using: .utf8),
                  let req = try? JSONDecoder().decode(WebhookTaskRequest.self, from: data) else {
                return httpResponse(status: 400, body: #"{"error":"Invalid JSON body"}"#)
            }

            guard let handler = onCreateTask else {
                return httpResponse(status: 500, body: #"{"error":"Server not configured"}"#)
            }

            let result = await handler(req)
            let responseBody = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? #"{"ok":true}"#
            return httpResponse(status: 201, body: responseBody)

        default:
            return httpResponse(status: 404, body: #"{"error":"Not found"}"#)
        }
    }

    private func httpResponse(status: Int, body: String) -> String {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 201: statusText = "Created"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }
        return "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }
}

// MARK: - Request / Response Models

package struct WebhookTaskRequest: Codable, Sendable {
    let projectId: String
    let title: String
    let description: String?
    let agentType: String?
}

package struct WebhookTaskResponse: Codable, Sendable {
    let taskId: String
    let status: String
}
