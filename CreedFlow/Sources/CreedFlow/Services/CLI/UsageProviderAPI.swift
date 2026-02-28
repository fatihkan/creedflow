import Foundation

// MARK: - Provider Usage Data

/// Aggregated usage data returned from a provider's API.
package struct ProviderUsageData: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let requestCount: Int
    let costUSD: Double?
}

// MARK: - Usage API Error

package enum UsageAPIError: LocalizedError, Sendable {
    case noAPIKey
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case networkError(String)

    package var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Admin API key"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .decodingError(let msg): return "Decode error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}

// MARK: - Anthropic Usage API

/// Fetches real usage data from the Anthropic Admin API.
/// GET https://api.anthropic.com/v1/organizations/usage
package enum AnthropicUsageAPI {

    /// Fetch usage for a given time range.
    /// - Parameters:
    ///   - adminKey: Anthropic admin API key (sk-ant-admin-...)
    ///   - startingAt: Start of the time window (ISO 8601)
    ///   - endingAt: End of the time window (ISO 8601)
    ///   - bucketWidth: "1h" or "1d"
    static func fetchUsage(
        adminKey: String,
        startingAt: Date,
        endingAt: Date,
        bucketWidth: String = "1d"
    ) async -> Result<ProviderUsageData, UsageAPIError> {
        guard !adminKey.isEmpty else { return .failure(.noAPIKey) }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/usage")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: startingAt)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: endingAt)),
            URLQueryItem(name: "bucket_width", value: bucketWidth),
        ]

        guard let url = components.url else {
            return .failure(.decodingError("Invalid URL"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.networkError("No HTTP response"))
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return .failure(.httpError(statusCode: http.statusCode, body: String(body.prefix(200))))
            }
            return parseAnthropicResponse(data)
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    private static func parseAnthropicResponse(_ data: Data) -> Result<ProviderUsageData, UsageAPIError> {
        // Response: { "data": [ { "bucket_start_time": "...", "results": [...] } ] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return .failure(.decodingError("Invalid JSON structure"))
        }

        var totalInput = 0
        var totalOutput = 0
        var totalCached = 0
        var totalRequests = 0

        for bucket in dataArray {
            guard let results = bucket["results"] as? [[String: Any]] else { continue }
            for result in results {
                totalInput += result["input_tokens"] as? Int ?? 0
                totalOutput += result["output_tokens"] as? Int ?? 0
                totalCached += result["cache_read_input_tokens"] as? Int ?? 0
                totalRequests += result["num_api_requests"] as? Int ?? 0
            }
        }

        // Estimate cost from tokens (Sonnet 4: $3/1M input, $15/1M output)
        let inputCost = Double(totalInput) / 1_000_000.0 * 3.0
        let outputCost = Double(totalOutput) / 1_000_000.0 * 15.0
        let cachedCost = Double(totalCached) / 1_000_000.0 * 0.3 // cached reads are 90% cheaper
        let estimatedCost = inputCost + outputCost + cachedCost

        return .success(ProviderUsageData(
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cachedInputTokens: totalCached,
            requestCount: totalRequests,
            costUSD: estimatedCost
        ))
    }
}

// MARK: - OpenAI Usage API

/// Fetches real usage data from the OpenAI Admin API.
/// GET https://api.openai.com/v1/organization/usage/completions
/// GET https://api.openai.com/v1/organization/costs
package enum OpenAIUsageAPI {

    /// Fetch token usage for a given time range.
    static func fetchUsage(
        adminKey: String,
        startTime: Date,
        endTime: Date,
        bucketWidth: String = "1d"
    ) async -> Result<ProviderUsageData, UsageAPIError> {
        guard !adminKey.isEmpty else { return .failure(.noAPIKey) }

        let startUnix = Int(startTime.timeIntervalSince1970)
        let endUnix = Int(endTime.timeIntervalSince1970)

        var components = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: "\(startUnix)"),
            URLQueryItem(name: "end_time", value: "\(endUnix)"),
            URLQueryItem(name: "bucket_width", value: bucketWidth),
        ]

        guard let url = components.url else {
            return .failure(.decodingError("Invalid URL"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.networkError("No HTTP response"))
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return .failure(.httpError(statusCode: http.statusCode, body: String(body.prefix(200))))
            }
            return parseOpenAIUsageResponse(data)
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    /// Fetch real USD cost for a given time range.
    static func fetchCost(
        adminKey: String,
        startTime: Date,
        endTime: Date
    ) async -> Result<Double, UsageAPIError> {
        guard !adminKey.isEmpty else { return .failure(.noAPIKey) }

        let startUnix = Int(startTime.timeIntervalSince1970)
        let endUnix = Int(endTime.timeIntervalSince1970)

        var components = URLComponents(string: "https://api.openai.com/v1/organization/costs")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: "\(startUnix)"),
            URLQueryItem(name: "end_time", value: "\(endUnix)"),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]

        guard let url = components.url else {
            return .failure(.decodingError("Invalid URL"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.networkError("No HTTP response"))
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return .failure(.httpError(statusCode: http.statusCode, body: String(body.prefix(200))))
            }
            return parseOpenAICostResponse(data)
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    private static func parseOpenAIUsageResponse(_ data: Data) -> Result<ProviderUsageData, UsageAPIError> {
        // Response: { "data": [ { "results": [ { "input_tokens": N, "output_tokens": N, "num_model_requests": N } ] } ] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return .failure(.decodingError("Invalid JSON structure"))
        }

        var totalInput = 0
        var totalOutput = 0
        var totalRequests = 0

        for bucket in dataArray {
            guard let results = bucket["results"] as? [[String: Any]] else { continue }
            for result in results {
                totalInput += result["input_tokens"] as? Int ?? 0
                totalOutput += result["output_tokens"] as? Int ?? 0
                totalRequests += result["num_model_requests"] as? Int ?? 0
            }
        }

        return .success(ProviderUsageData(
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cachedInputTokens: 0,
            requestCount: totalRequests,
            costUSD: nil // cost comes from the separate /costs endpoint
        ))
    }

    private static func parseOpenAICostResponse(_ data: Data) -> Result<Double, UsageAPIError> {
        // Response: { "data": [ { "results": [ { "amount": { "value": 0.123, "currency": "usd" } } ] } ] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return .failure(.decodingError("Invalid JSON structure"))
        }

        var totalCost = 0.0
        for bucket in dataArray {
            guard let results = bucket["results"] as? [[String: Any]] else { continue }
            for result in results {
                if let amount = result["amount"] as? [String: Any],
                   let value = amount["value"] as? Double {
                    // API returns cents, convert to dollars
                    totalCost += value / 100.0
                }
            }
        }

        return .success(totalCost)
    }
}
