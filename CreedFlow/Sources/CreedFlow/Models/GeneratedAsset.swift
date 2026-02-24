import Foundation
import GRDB

/// Tracks files produced by creative agents (images, videos, audio, designs, documents).
package struct GeneratedAsset: Codable, Identifiable, Equatable {
    package var id: UUID
    package var projectId: UUID
    package var taskId: UUID
    package var agentType: AgentTask.AgentType
    package var assetType: AssetType
    package var name: String
    package var assetDescription: String
    package var filePath: String
    package var mimeType: String?
    package var fileSize: Int64?
    package var sourceUrl: String?
    package var metadata: String?   // JSON blob for extra info
    package var status: Status
    package var reviewTaskId: UUID?
    package var createdAt: Date
    package var updatedAt: Date

    package enum AssetType: String, Codable, CaseIterable, DatabaseValueConvertible {
        case image
        case video
        case audio
        case design
        case document
    }

    package enum Status: String, Codable, CaseIterable, DatabaseValueConvertible {
        case generated
        case reviewed
        case approved
        case rejected
    }

    package init(
        id: UUID = UUID(),
        projectId: UUID,
        taskId: UUID,
        agentType: AgentTask.AgentType,
        assetType: AssetType,
        name: String,
        assetDescription: String = "",
        filePath: String,
        mimeType: String? = nil,
        fileSize: Int64? = nil,
        sourceUrl: String? = nil,
        metadata: String? = nil,
        status: Status = .generated,
        reviewTaskId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.agentType = agentType
        self.assetType = assetType
        self.name = name
        self.assetDescription = assetDescription
        self.filePath = filePath
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.sourceUrl = sourceUrl
        self.metadata = metadata
        self.status = status
        self.reviewTaskId = reviewTaskId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Persistence

extension GeneratedAsset: FetchableRecord, PersistableRecord {
    package static let databaseTableName = "generatedAsset"

    // Use explicit coding keys so DB column "assetDescription" maps correctly
    enum CodingKeys: String, CodingKey {
        case id, projectId, taskId, agentType, assetType, name
        case assetDescription, filePath, mimeType, fileSize
        case sourceUrl, metadata, status, reviewTaskId
        case createdAt, updatedAt
    }

    static let project = belongsTo(Project.self)
    static let task = belongsTo(AgentTask.self, using: ForeignKey(["taskId"]))

    var project: QueryInterfaceRequest<Project> {
        request(for: GeneratedAsset.project)
    }

    var task: QueryInterfaceRequest<AgentTask> {
        request(for: GeneratedAsset.task)
    }
}
