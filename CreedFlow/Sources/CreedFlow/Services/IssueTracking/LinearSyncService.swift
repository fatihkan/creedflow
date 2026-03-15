import Foundation
import GRDB
import os.log

/// Syncs issues from Linear via GraphQL API.
package actor LinearSyncService {
    private let logger = Logger(subsystem: "com.creedflow", category: "LinearSync")
    private let dbQueue: DatabaseQueue
    private let endpoint = URL(string: "https://api.linear.app/graphql")!

    package init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Import issues from Linear and create AgentTasks + IssueMappings.
    package func importIssues(config: IssueTrackingConfig) async throws -> [IssueMapping] {
        guard let creds = parseCredentials(config.credentialsJSON),
              let apiKey = creds["apiKey"], !apiKey.isEmpty else {
            throw IssueTrackingError.invalidCredentials
        }

        let configData = parseConfig(config.configJSON)
        let teamId = configData["teamId"] ?? ""
        let stateFilter = parseStringArray(configData["stateFilter"])
        let agentType = configData["agentType"] ?? "coder"

        let issues = try await fetchIssues(apiKey: apiKey, teamId: teamId, stateFilter: stateFilter)

        var mappings: [IssueMapping] = []

        for issue in issues {
            let mapping = try await dbQueue.write { db -> IssueMapping in
                // Check for existing mapping to avoid duplicates
                let existing = try IssueMapping
                    .filter(Column("configId") == config.id)
                    .filter(Column("externalIssueId") == issue.id)
                    .fetchOne(db)

                if let existing {
                    return existing
                }

                // Create AgentTask
                let taskId = UUID()
                var task = AgentTask(
                    id: taskId,
                    projectId: config.projectId,
                    agentType: AgentTask.AgentType(rawValue: agentType) ?? .coder,
                    title: issue.title,
                    description: issue.description ?? issue.title
                )
                task.priority = issue.priority
                try task.insert(db)

                // Create IssueMapping
                let mapping = IssueMapping(
                    configId: config.id,
                    taskId: taskId,
                    externalIssueId: issue.id,
                    externalIdentifier: issue.identifier,
                    externalUrl: issue.url
                )
                try mapping.insert(db)

                return mapping
            }
            mappings.append(mapping)
        }

        // Update lastSyncAt
        try await dbQueue.write { db in
            var updated = config
            updated.lastSyncAt = Date()
            updated.updatedAt = Date()
            try updated.update(db)
        }

        logger.info("Imported \(mappings.count) issues from Linear for config \(config.name)")
        return mappings
    }

    /// Sync task status back to Linear by updating issue state.
    package func syncBackStatus(mapping: IssueMapping, task: AgentTask, config: IssueTrackingConfig) async throws {
        guard config.syncBackEnabled else { return }

        guard let creds = parseCredentials(config.credentialsJSON),
              let apiKey = creds["apiKey"], !apiKey.isEmpty else {
            throw IssueTrackingError.invalidCredentials
        }

        let configData = parseConfig(config.configJSON)
        guard let doneStateId = configData["doneStateId"], !doneStateId.isEmpty else {
            logger.warning("No doneStateId configured — skipping sync-back")
            return
        }

        // Only sync back completed tasks
        guard task.status == .passed else { return }

        let mutation = """
        mutation {
            issueUpdate(id: "\(mapping.externalIssueId)", input: { stateId: "\(doneStateId)" }) {
                success
            }
        }
        """

        let (_, response) = try await performGraphQL(apiKey: apiKey, query: mutation)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            try await dbQueue.write { db in
                var m = mapping
                m.syncStatus = .syncFailed
                m.lastSyncedAt = Date()
                try m.update(db)
            }
            throw IssueTrackingError.apiError("Failed to update Linear issue state")
        }

        try await dbQueue.write { db in
            var m = mapping
            m.syncStatus = .synced
            m.lastSyncedAt = Date()
            try m.update(db)
        }

        logger.info("Synced status back for \(mapping.externalIdentifier)")
    }

    // MARK: - Private

    private struct LinearIssue {
        let id: String
        let identifier: String
        let title: String
        let description: String?
        let priority: Int
        let url: String?
    }

    private func fetchIssues(apiKey: String, teamId: String, stateFilter: [String]) async throws -> [LinearIssue] {
        var filterClause = ""
        if !teamId.isEmpty {
            filterClause += "team: { id: { eq: \"\(teamId)\" } }"
        }
        if !stateFilter.isEmpty {
            let stateNames = stateFilter.map { "\"\($0)\"" }.joined(separator: ", ")
            if !filterClause.isEmpty { filterClause += ", " }
            filterClause += "state: { name: { in: [\(stateNames)] } }"
        }

        let filterArg = filterClause.isEmpty ? "" : "(filter: { \(filterClause) })"

        let query = """
        query {
            issues\(filterArg) {
                nodes {
                    id
                    identifier
                    title
                    description
                    priority
                    url
                }
            }
        }
        """

        let (data, _) = try await performGraphQL(apiKey: apiKey, query: query)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let issuesObj = dataObj["issues"] as? [String: Any],
              let nodes = issuesObj["nodes"] as? [[String: Any]] else {
            // Check for errors
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let message = firstError["message"] as? String {
                throw IssueTrackingError.apiError(message)
            }
            throw IssueTrackingError.apiError("Unexpected response format from Linear API")
        }

        return nodes.compactMap { node -> LinearIssue? in
            guard let id = node["id"] as? String,
                  let identifier = node["identifier"] as? String,
                  let title = node["title"] as? String else { return nil }
            return LinearIssue(
                id: id,
                identifier: identifier,
                title: title,
                description: node["description"] as? String,
                priority: node["priority"] as? Int ?? 0,
                url: node["url"] as? String
            )
        }
    }

    private func performGraphQL(apiKey: String, query: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await URLSession.shared.data(for: request)
    }

    private func parseCredentials(_ json: String) -> [String: String]? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return dict
    }

    private func parseConfig(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in dict {
            if let str = value as? String {
                result[key] = str
            } else if let arr = value as? [String] {
                result[key] = arr.joined(separator: ",")
            }
        }
        return result
    }

    private func parseStringArray(_ commaSeparated: String?) -> [String] {
        guard let str = commaSeparated, !str.isEmpty else { return [] }
        return str.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
