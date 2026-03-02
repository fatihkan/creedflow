import Foundation
import GRDB

/// Tracks real API provider usage for sidebar display.
/// Polls Anthropic/OpenAI admin APIs every 5 minutes; Gemini falls back to local DB.
@Observable
final class CLIUsageStore {

    enum FetchStatus: Sendable {
        case idle
        case loading
        case loaded(Date)
        case error(String)
    }

    struct UsageWindow {
        var tokens: Int = 0
        var cost: Double = 0
        var taskCount: Int = 0
    }

    struct BackendUsage {
        let backend: CLIBackendType
        var last4h: UsageWindow = UsageWindow()
        var lastWeek: UsageWindow = UsageWindow()
        var status: FetchStatus = .idle
    }

    private(set) var usages: [CLIBackendType: BackendUsage] = [:]
    private var pollingTask: Task<Void, Never>?

    /// Cloud backends we track (local LLMs are unlimited, no need to show).
    static let trackedBackends: [CLIBackendType] = [.claude, .codex, .gemini]

    func usage(for backend: CLIBackendType) -> BackendUsage {
        usages[backend] ?? BackendUsage(backend: backend)
    }

    /// Start polling provider APIs every 5 minutes. Gemini uses local DB fallback.
    func startPolling(dbQueue: DatabaseQueue) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            // Initial fetch immediately
            await self?.fetchAll(dbQueue: dbQueue)

            // Then poll every 5 minutes
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if Task.isCancelled { break }
                await self?.fetchAll(dbQueue: dbQueue)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Force an immediate refresh of all providers.
    func refresh(dbQueue: DatabaseQueue) {
        Task { await fetchAll(dbQueue: dbQueue) }
    }

    // MARK: - Fetch All Providers

    private func fetchAll(dbQueue: DatabaseQueue) async {
        // Mark all tracked backends as loading
        for backend in Self.trackedBackends {
            var u = usages[backend] ?? BackendUsage(backend: backend)
            u.status = .loading
            usages[backend] = u
        }

        // Fetch all 3 providers in parallel
        await withTaskGroup(of: (CLIBackendType, BackendUsage).self) { group in
            group.addTask { await (.claude, self.fetchAnthropic()) }
            group.addTask { await (.codex, self.fetchOpenAI()) }
            group.addTask { await (.gemini, self.fetchGeminiFromDB(dbQueue: dbQueue)) }

            for await (backend, usage) in group {
                usages[backend] = usage
            }
        }
    }

    // MARK: - Anthropic

    private func fetchAnthropic() async -> BackendUsage {
        let adminKey = Self.resolveKey(
            userDefaultsKey: "anthropicAdminAPIKey",
            envVar: "ANTHROPIC_ADMIN_API_KEY"
        )

        guard !adminKey.isEmpty else {
            return BackendUsage(backend: .claude, status: .error("No Admin API key"))
        }

        let now = Date()
        let fourHoursAgo = now.addingTimeInterval(-4 * 3600)
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)

        // Fetch both time windows in parallel
        async let result4h = AnthropicUsageAPI.fetchUsage(
            adminKey: adminKey, startingAt: fourHoursAgo, endingAt: now, bucketWidth: "1h"
        )
        async let resultWeek = AnthropicUsageAPI.fetchUsage(
            adminKey: adminKey, startingAt: weekAgo, endingAt: now, bucketWidth: "1d"
        )

        let r4h = await result4h
        let rWeek = await resultWeek

        var usage = BackendUsage(backend: .claude)

        switch r4h {
        case .success(let data):
            usage.last4h = UsageWindow(
                tokens: data.inputTokens + data.outputTokens,
                cost: data.costUSD ?? 0,
                taskCount: data.requestCount
            )
        case .failure(let err):
            return BackendUsage(backend: .claude, status: .error(err.localizedDescription))
        }

        switch rWeek {
        case .success(let data):
            usage.lastWeek = UsageWindow(
                tokens: data.inputTokens + data.outputTokens,
                cost: data.costUSD ?? 0,
                taskCount: data.requestCount
            )
        case .failure(let err):
            return BackendUsage(backend: .claude, status: .error(err.localizedDescription))
        }

        usage.status = .loaded(Date())
        return usage
    }

    // MARK: - OpenAI (Codex)

    private func fetchOpenAI() async -> BackendUsage {
        let adminKey = Self.resolveKey(
            userDefaultsKey: "openaiAdminAPIKey",
            envVar: "OPENAI_ADMIN_KEY"
        )

        guard !adminKey.isEmpty else {
            return BackendUsage(backend: .codex, status: .error("No Admin API key"))
        }

        let now = Date()
        let fourHoursAgo = now.addingTimeInterval(-4 * 3600)
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)

        // Fetch usage + cost in parallel for both windows
        async let usage4h = OpenAIUsageAPI.fetchUsage(
            adminKey: adminKey, startTime: fourHoursAgo, endTime: now, bucketWidth: "1h"
        )
        async let usageWeek = OpenAIUsageAPI.fetchUsage(
            adminKey: adminKey, startTime: weekAgo, endTime: now, bucketWidth: "1d"
        )
        async let cost4h = OpenAIUsageAPI.fetchCost(
            adminKey: adminKey, startTime: fourHoursAgo, endTime: now
        )
        async let costWeek = OpenAIUsageAPI.fetchCost(
            adminKey: adminKey, startTime: weekAgo, endTime: now
        )

        let r4h = await usage4h
        let rWeek = await usageWeek
        let c4h = await cost4h
        let cWeek = await costWeek

        var usage = BackendUsage(backend: .codex)

        switch r4h {
        case .success(let data):
            let cost = (try? c4h.get()) ?? 0
            usage.last4h = UsageWindow(
                tokens: data.inputTokens + data.outputTokens,
                cost: cost,
                taskCount: data.requestCount
            )
        case .failure(let err):
            return BackendUsage(backend: .codex, status: .error(err.localizedDescription))
        }

        switch rWeek {
        case .success(let data):
            let cost = (try? cWeek.get()) ?? 0
            usage.lastWeek = UsageWindow(
                tokens: data.inputTokens + data.outputTokens,
                cost: cost,
                taskCount: data.requestCount
            )
        case .failure(let err):
            return BackendUsage(backend: .codex, status: .error(err.localizedDescription))
        }

        usage.status = .loaded(Date())
        return usage
    }

    // MARK: - Gemini (Local DB Fallback)

    private func fetchGeminiFromDB(dbQueue: DatabaseQueue) async -> BackendUsage {
        do {
            let result = try await dbQueue.read { db -> BackendUsage in
                let now = Date()
                let fourHoursAgo = now.addingTimeInterval(-4 * 3600)
                let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)

                var usage = BackendUsage(backend: .gemini)

                // Last 4 hours
                let rows4h = try Row.fetchAll(db, sql: """
                    SELECT COALESCE(SUM(inputTokens + outputTokens), 0) AS totalTokens,
                           COALESCE(SUM(costUSD), 0) AS totalCost,
                           COUNT(*) AS taskCount
                    FROM costTracking
                    WHERE createdAt >= ? AND backend = ?
                    """, arguments: [fourHoursAgo, CLIBackendType.gemini.rawValue])

                if let row = rows4h.first {
                    usage.last4h = UsageWindow(
                        tokens: row["totalTokens"],
                        cost: row["totalCost"],
                        taskCount: row["taskCount"]
                    )
                }

                // Last 7 days
                let rows7d = try Row.fetchAll(db, sql: """
                    SELECT COALESCE(SUM(inputTokens + outputTokens), 0) AS totalTokens,
                           COALESCE(SUM(costUSD), 0) AS totalCost,
                           COUNT(*) AS taskCount
                    FROM costTracking
                    WHERE createdAt >= ? AND backend = ?
                    """, arguments: [weekAgo, CLIBackendType.gemini.rawValue])

                if let row = rows7d.first {
                    usage.lastWeek = UsageWindow(
                        tokens: row["totalTokens"],
                        cost: row["totalCost"],
                        taskCount: row["taskCount"]
                    )
                }

                usage.status = .loaded(Date())
                return usage
            }
            return result
        } catch {
            return BackendUsage(backend: .gemini, status: .error("DB read failed"))
        }
    }

    // MARK: - Helpers

    private static func resolveKey(userDefaultsKey: String, envVar: String) -> String {
        let stored = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
        if !stored.isEmpty { return stored }
        return ProcessInfo.processInfo.environment[envVar] ?? ""
    }
}
