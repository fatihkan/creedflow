import Foundation
import GRDB

/// Periodically probes all CLI backends for availability.
/// Binary backends are checked via `--version` with a 5s timeout.
/// LM Studio is checked via HTTP GET to localhost:1234/v1/models.
/// Emits notifications only on status transitions to avoid spam.
actor BackendHealthMonitor {
    private let dbQueue: DatabaseQueue
    private let notificationService: NotificationService
    private let checkInterval: TimeInterval = 60
    private var pollingTask: Task<Void, Never>?
    private var lastStatus: [CLIBackendType: HealthEvent.HealthStatus] = [:]

    /// Current health status for each backend (read from UI via async).
    private(set) var currentStatus: [CLIBackendType: HealthEvent.HealthStatus] = [:]

    init(dbQueue: DatabaseQueue, notificationService: NotificationService) {
        self.dbQueue = dbQueue
        self.notificationService = notificationService
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkAll()
                try? await Task.sleep(for: .seconds(self?.checkInterval ?? 60))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Get health status for a specific backend type.
    func status(for type: CLIBackendType) -> HealthEvent.HealthStatus {
        currentStatus[type] ?? .unknown
    }

    // MARK: - Private

    private func checkAll() async {
        for backendType in CLIBackendType.allCases {
            guard isEnabled(backendType) else {
                // Skip disabled backends — mark unknown
                updateStatus(backendType, status: .unknown)
                continue
            }
            await checkBackend(backendType)
        }
    }

    private func checkBackend(_ type: CLIBackendType) async {
        let start = Date()

        if type == .lmstudio {
            await checkLMStudio(startTime: start)
            return
        }

        guard let path = resolvedPath(for: type) else {
            recordAndNotify(type, status: .unhealthy, startTime: start, error: "Binary not found")
            return
        }

        // Check binary exists
        guard FileManager.default.isExecutableFile(atPath: path) else {
            recordAndNotify(type, status: .unhealthy, startTime: start, error: "Not executable: \(path)")
            return
        }

        // Run --version with 5s timeout
        do {
            let output = try await runWithTimeout(path: path, arguments: ["--version"], timeout: 5)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let status: HealthEvent.HealthStatus = elapsed > 3000 ? .degraded : .healthy
            recordAndNotify(type, status: status, startTime: start, responseTimeMs: elapsed)
        } catch {
            recordAndNotify(type, status: .unhealthy, startTime: start, error: error.localizedDescription)
        }
    }

    private func checkLMStudio(startTime: Date) async {
        let url = URL(string: "http://localhost:1234/v1/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            if let code = httpResponse?.statusCode, (200..<300).contains(code) {
                let status: HealthEvent.HealthStatus = elapsed > 3000 ? .degraded : .healthy
                recordAndNotify(.lmstudio, status: status, startTime: startTime, responseTimeMs: elapsed)
            } else {
                recordAndNotify(.lmstudio, status: .unhealthy, startTime: startTime,
                                error: "HTTP \(httpResponse?.statusCode ?? 0)")
            }
        } catch {
            recordAndNotify(.lmstudio, status: .unhealthy, startTime: startTime,
                            error: error.localizedDescription)
        }
    }

    private func recordAndNotify(
        _ type: CLIBackendType,
        status: HealthEvent.HealthStatus,
        startTime: Date,
        responseTimeMs: Int? = nil,
        error: String? = nil
    ) {
        let elapsed = responseTimeMs ?? Int(Date().timeIntervalSince(startTime) * 1000)
        let previous = lastStatus[type] ?? .unknown

        // Record to DB
        let event = HealthEvent(
            targetType: .backend,
            targetName: type.rawValue,
            status: status,
            responseTimeMs: elapsed,
            errorMessage: error
        )
        try? dbQueue.write { db in
            var e = event
            try e.insert(db)
        }

        // Update current status
        updateStatus(type, status: status)

        // Emit notification on transition only (suppress unknown → healthy)
        if previous != status && !(previous == .unknown && status == .healthy) {
            let severity: AppNotification.Severity
            let title: String
            switch status {
            case .healthy:
                severity = .success
                title = "\(type.displayName) Recovered"
            case .degraded:
                severity = .warning
                title = "\(type.displayName) Degraded"
            case .unhealthy:
                severity = .error
                title = "\(type.displayName) Unhealthy"
            case .unknown:
                return // Don't notify on unknown
            }
            let message = error ?? "Response time: \(elapsed)ms"
            Task {
                await notificationService.emit(
                    category: .backendHealth,
                    severity: severity,
                    title: title,
                    message: message
                )
            }
        }
    }

    private func updateStatus(_ type: CLIBackendType, status: HealthEvent.HealthStatus) {
        lastStatus[type] = status
        currentStatus[type] = status
    }

    // MARK: - Helpers

    private func isEnabled(_ type: CLIBackendType) -> Bool {
        UserDefaults.standard.object(forKey: "\(type.rawValue)Enabled") as? Bool ?? (type != .ollama && type != .lmstudio && type != .llamacpp && type != .mlx)
    }

    private func resolvedPath(for type: CLIBackendType) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let stored = UserDefaults.standard.string(forKey: "\(type.rawValue)Path") ?? ""

        if !stored.isEmpty { return stored }

        switch type {
        case .claude: return "\(home)/.local/bin/claude"
        case .codex: return "/usr/local/bin/codex"
        case .gemini: return "/usr/local/bin/gemini"
        case .opencode: return "/usr/local/bin/opencode"
        case .openclaw: return "/usr/local/bin/openclaw"
        case .ollama: return "/usr/local/bin/ollama"
        case .llamacpp: return "/opt/homebrew/bin/llama-cli"
        case .mlx: return "\(home)/.local/bin/mlx_lm.generate"
        case .lmstudio: return nil // HTTP-based, not a binary
        }
    }

    private func runWithTimeout(path: String, arguments: [String], timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.environment = ProcessInfo.processInfo.environment
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw CancellationError()
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
