import Foundation
import GRDB

package struct AgentPersona: Codable, Identifiable, Equatable {
    package var id: UUID
    package var name: String
    package var description: String
    package var systemPrompt: String
    package var agentTypes: [AgentTask.AgentType]
    package var tags: [String]
    package var isBuiltIn: Bool
    package var isEnabled: Bool
    package var createdAt: Date
    package var updatedAt: Date

    package init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        systemPrompt: String,
        agentTypes: [AgentTask.AgentType] = [],
        tags: [String] = [],
        isBuiltIn: Bool = false,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.agentTypes = agentTypes
        self.tags = tags
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension AgentPersona: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "agentPersona"

    package enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let description = Column(CodingKeys.description)
        static let systemPrompt = Column(CodingKeys.systemPrompt)
        static let agentTypes = Column(CodingKeys.agentTypes)
        static let tags = Column(CodingKeys.tags)
        static let isBuiltIn = Column(CodingKeys.isBuiltIn)
        static let isEnabled = Column(CodingKeys.isEnabled)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    package init(row: Row) throws {
        id = row["id"]
        name = row["name"]
        description = row["description"]
        systemPrompt = row["systemPrompt"]
        isBuiltIn = row["isBuiltIn"]
        isEnabled = row["isEnabled"]
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]

        // Decode JSON arrays
        let agentTypesJSON: String = row["agentTypes"]
        if let data = agentTypesJSON.data(using: .utf8),
           let strings = try? JSONDecoder().decode([String].self, from: data) {
            agentTypes = strings.compactMap { AgentTask.AgentType(rawValue: $0) }
        } else {
            agentTypes = []
        }

        let tagsJSON: String = row["tags"]
        if let data = tagsJSON.data(using: .utf8),
           let strings = try? JSONDecoder().decode([String].self, from: data) {
            tags = strings
        } else {
            tags = []
        }
    }

    package func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
        container["description"] = description
        container["systemPrompt"] = systemPrompt
        container["isBuiltIn"] = isBuiltIn
        container["isEnabled"] = isEnabled
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt

        // Encode JSON arrays
        let agentTypeStrings = agentTypes.map { $0.rawValue }
        if let data = try? JSONEncoder().encode(agentTypeStrings) {
            container["agentTypes"] = String(data: data, encoding: .utf8) ?? "[]"
        } else {
            container["agentTypes"] = "[]"
        }

        if let data = try? JSONEncoder().encode(tags) {
            container["tags"] = String(data: data, encoding: .utf8) ?? "[]"
        } else {
            container["tags"] = "[]"
        }
    }
}

// MARK: - Queries

extension AgentPersona {
    /// All personas ordered by name.
    package static func all() -> QueryInterfaceRequest<AgentPersona> {
        AgentPersona.order(Columns.name)
    }

    /// Only enabled personas.
    package static func enabled() -> QueryInterfaceRequest<AgentPersona> {
        AgentPersona.filter(Columns.isEnabled == true).order(Columns.name)
    }

    /// Find persona by exact name.
    package static func byName(_ name: String) -> QueryInterfaceRequest<AgentPersona> {
        AgentPersona.filter(Columns.name == name)
    }

    /// Enabled personas whose agentTypes JSON contains the given type.
    /// Uses SQLite LIKE for JSON array search since agentTypes is stored as JSON text.
    package static func forAgentType(_ type: AgentTask.AgentType) -> QueryInterfaceRequest<AgentPersona> {
        AgentPersona
            .filter(Columns.isEnabled == true)
            .filter(Columns.agentTypes.like("%\"\(type.rawValue)\"%"))
            .order(Columns.name)
    }
}
