import Foundation
import GRDB

/// Central service that routes publishing requests to the appropriate publisher,
/// handles scheduled publications, and manages publication records.
actor ContentPublishingService {
    private let dbQueue: DatabaseQueue
    private let exporter: ContentExporter
    private let publishers: [PublishingChannel.ChannelType: any PublisherProtocol]
    private var pollingTask: Task<Void, Never>?

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        self.exporter = ContentExporter()
        self.publishers = [
            .medium: MediumPublisher(),
            .wordpress: WordPressPublisher(),
            .twitter: TwitterPublisher(),
            .linkedin: LinkedInPublisher(),
        ]
    }

    /// Start the scheduled publication polling loop.
    func startScheduledPublishing() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.processScheduledPublications()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Stop the polling loop.
    func stopScheduledPublishing() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Publish an asset to a specific channel immediately.
    func publish(
        assetId: UUID,
        channelId: UUID,
        format: Publication.ExportFormat = .markdown,
        options: PublishOptions
    ) async throws -> Publication {
        // Fetch asset and channel
        let (asset, channel) = try await dbQueue.read { db -> (GeneratedAsset, PublishingChannel) in
            guard let asset = try GeneratedAsset.fetchOne(db, id: assetId) else {
                throw PublishingError.apiError("Asset not found: \(assetId)")
            }
            guard let channel = try PublishingChannel.fetchOne(db, id: channelId) else {
                throw PublishingError.channelNotFound(channelId)
            }
            return (asset, channel)
        }

        guard let publisher = publishers[channel.channelType] else {
            throw PublishingError.unsupportedFormat(channel.channelType.rawValue)
        }

        // Create publication record
        var publication = Publication(
            assetId: assetId,
            projectId: asset.projectId,
            channelId: channelId,
            status: .publishing,
            exportFormat: format
        )
        try await dbQueue.write { db in
            try publication.insert(db)
        }

        do {
            // Export content
            let exported = try await exporter.export(
                filePath: asset.filePath,
                title: asset.name,
                format: format
            )

            // Parse credentials from channel JSON
            let credentials = parseCredentials(channel.credentialsJSON)
            let publishOptions = PublishOptions(
                title: options.title,
                tags: options.tags,
                scheduledAt: nil,
                isDraft: options.isDraft,
                credentials: credentials
            )

            // Publish
            let result = try await publisher.publish(content: exported, options: publishOptions)

            // Update publication record
            publication.status = .published
            publication.externalId = result.externalId
            publication.publishedUrl = result.url
            publication.publishedAt = result.publishedAt
            publication.updatedAt = Date()
            try await dbQueue.write { db in
                try publication.update(db)
            }

            return publication

        } catch {
            // Mark as failed
            publication.status = .failed
            publication.errorMessage = error.localizedDescription
            publication.updatedAt = Date()
            try? await dbQueue.write { db in
                try publication.update(db)
            }
            throw error
        }
    }

    /// Schedule an asset for future publication.
    func schedule(
        assetId: UUID,
        channelId: UUID,
        format: Publication.ExportFormat = .markdown,
        scheduledAt: Date,
        title: String,
        tags: [String] = []
    ) async throws -> Publication {
        let asset = try await dbQueue.read { db in
            try GeneratedAsset.fetchOne(db, id: assetId)
        }
        guard let asset else {
            throw PublishingError.apiError("Asset not found: \(assetId)")
        }

        var publication = Publication(
            assetId: assetId,
            projectId: asset.projectId,
            channelId: channelId,
            status: .scheduled,
            scheduledAt: scheduledAt,
            exportFormat: format
        )
        try await dbQueue.write { db in
            try publication.insert(db)
        }
        return publication
    }

    /// Get all enabled publishing channels.
    func enabledChannels() async throws -> [PublishingChannel] {
        try await dbQueue.read { db in
            try PublishingChannel
                .filter(Column("isEnabled") == true)
                .fetchAll(db)
        }
    }

    // MARK: - Private

    /// Process any scheduled publications that are due.
    private func processScheduledPublications() async {
        let duePublications: [Publication]
        do {
            duePublications = try await dbQueue.read { db in
                try Publication
                    .filter(Column("status") == Publication.Status.scheduled.rawValue)
                    .filter(Column("scheduledAt") <= Date())
                    .fetchAll(db)
            }
        } catch {
            return
        }

        for pub in duePublications {
            let options = PublishOptions(title: "", tags: [])
            _ = try? await publish(
                assetId: pub.assetId,
                channelId: pub.channelId,
                format: pub.exportFormat,
                options: options
            )
        }
    }

    private func parseCredentials(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}
