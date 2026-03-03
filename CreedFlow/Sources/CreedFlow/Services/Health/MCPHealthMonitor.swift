import Foundation
import GRDB

/// Periodically checks enabled MCP server configurations for health.
/// Spawns the server process briefly and checks if it stays running for 1 second.
/// Emits notifications on status transitions only.
actor MCPHealthMonitor {
    private let dbQueue: DatabaseQueue
    private let notificationService: NotificationService
    private let checkInterval: TimeInterval = 120
    private var pollingTask: Task<Void, Never>?
    private var lastStatus: [String: HealthEvent.HealthStatus] = [:]

    /// Current health status keyed by MCP server name.
    private(set) var currentStatus: [String: HealthEvent.HealthStatus] = [:]

    init(dbQueue: DatabaseQueue, notificationService: NotificationService) {
        self.dbQueue = dbQueue
        self.notificationService = notificationService
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkAll()
                try? await Task.sleep(for: .seconds(self?.checkInterval ?? 120))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Get health status for a specific MCP server.
    func status(for name: String) -> HealthEvent.HealthStatus {
        currentStatus[name] ?? .unknown
    }

    // MARK: - Private

    private func checkAll() async {
        let configs: [MCPServerConfig]
        do {
            configs = try await dbQueue.read { db in
                try MCPServerConfig
                    .filter(Column("isEnabled") == true)
                    .fetchAll(db)
            }
        } catch {
            return
        }

        for config in configs {
            await checkServer(config)
        }
    }

    private func checkServer(_ config: MCPServerConfig) async {
        let start = Date()
        let name = config.name

        // Check if the command binary exists
        let command = config.command
        guard FileManager.default.isExecutableFile(atPath: command) else {
            recordAndNotify(name, status: .unhealthy, startTime: start,
                            error: "Binary not found: \(command)")
            return
        }

        // Spawn process and check if it survives for 1 second
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = config.decodedArguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            // Set environment variables
            var env = ProcessInfo.processInfo.environment
            for (key, value) in config.decodedEnvironmentVars {
                env[key] = value
            }
            process.environment = env

            try process.run()

            // Wait 1 second and check if still running
            try await Task.sleep(for: .seconds(1))

            let isAlive = process.isRunning
            process.terminate()

            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            if isAlive {
                recordAndNotify(name, status: .healthy, startTime: start, responseTimeMs: elapsed)
            } else {
                recordAndNotify(name, status: .unhealthy, startTime: start,
                                error: "Process exited with code \(process.terminationStatus)")
            }
        } catch {
            recordAndNotify(name, status: .unhealthy, startTime: start,
                            error: error.localizedDescription)
        }
    }

    private func recordAndNotify(
        _ name: String,
        status: HealthEvent.HealthStatus,
        startTime: Date,
        responseTimeMs: Int? = nil,
        error: String? = nil
    ) {
        let elapsed = responseTimeMs ?? Int(Date().timeIntervalSince(startTime) * 1000)
        let previous = lastStatus[name] ?? .unknown

        // Record to DB
        let event = HealthEvent(
            targetType: .mcp,
            targetName: name,
            status: status,
            responseTimeMs: elapsed,
            errorMessage: error
        )
        try? dbQueue.write { db in
            var e = event
            try e.insert(db)
        }

        // Update current status
        lastStatus[name] = status
        currentStatus[name] = status

        // Emit notification on transition only (suppress unknown → healthy)
        if previous != status && !(previous == .unknown && status == .healthy) {
            let severity: AppNotification.Severity
            let title: String
            switch status {
            case .healthy:
                severity = .success
                title = "MCP Server \"\(name)\" Recovered"
            case .degraded:
                severity = .warning
                title = "MCP Server \"\(name)\" Degraded"
            case .unhealthy:
                severity = .error
                title = "MCP Server \"\(name)\" Unhealthy"
            case .unknown:
                return
            }
            let message = error ?? "Response time: \(elapsed)ms"
            Task {
                await notificationService.emit(
                    category: .mcpHealth,
                    severity: severity,
                    title: title,
                    message: message
                )
            }
        }
    }
}
