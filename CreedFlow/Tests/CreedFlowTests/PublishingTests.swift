import Foundation
import GRDB
@testable import CreedFlowLib

// MARK: - PublishingChannel Tests

enum PublishingChannelTests {
    static func runAll() {
        testInsertAndFetch()
        testChannelTypeEnum()
        testFilterByEnabled()
        testFilterByChannelType()
        testUpdateCredentials()
        testDisableChannel()
        print("  PublishingChannelTests: 6/6 passed")
    }

    static func testInsertAndFetch() {
        let appDb = try! AppDatabase.makeEmpty()
        let channelId = UUID()

        try! appDb.dbQueue.write { db in
            var channel = PublishingChannel(
                id: channelId,
                name: "My Medium",
                channelType: .medium,
                credentialsJSON: "{\"token\":\"abc123\"}",
                isEnabled: true,
                defaultTags: "swift,ios"
            )
            try channel.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try PublishingChannel.fetchOne(db, id: channelId)
        }

        assertTrue(fetched != nil)
        assertEq(fetched!.name, "My Medium")
        assertEq(fetched!.channelType, .medium)
        assertEq(fetched!.credentialsJSON, "{\"token\":\"abc123\"}")
        assertTrue(fetched!.isEnabled)
        assertEq(fetched!.defaultTags, "swift,ios")
    }

    static func testChannelTypeEnum() {
        let types: [PublishingChannel.ChannelType] = [.medium, .wordpress, .twitter, .linkedin, .devTo]
        assertEq(types.count, 5)
        assertEq(PublishingChannel.ChannelType.medium.rawValue, "medium")
        assertEq(PublishingChannel.ChannelType.wordpress.rawValue, "wordpress")
        assertEq(PublishingChannel.ChannelType.twitter.rawValue, "twitter")
        assertEq(PublishingChannel.ChannelType.linkedin.rawValue, "linkedin")
        assertEq(PublishingChannel.ChannelType.devTo.rawValue, "devTo")
    }

    static func testFilterByEnabled() {
        let appDb = try! AppDatabase.makeEmpty()

        try! appDb.dbQueue.write { db in
            var ch1 = PublishingChannel(name: "Active", channelType: .medium, isEnabled: true)
            try ch1.insert(db)
            var ch2 = PublishingChannel(name: "Disabled", channelType: .twitter, isEnabled: false)
            try ch2.insert(db)
            var ch3 = PublishingChannel(name: "Also Active", channelType: .wordpress, isEnabled: true)
            try ch3.insert(db)
        }

        let enabled = try! appDb.dbQueue.read { db in
            try PublishingChannel.filter(Column("isEnabled") == true).fetchAll(db)
        }
        assertEq(enabled.count, 2)
    }

    static func testFilterByChannelType() {
        let appDb = try! AppDatabase.makeEmpty()

        try! appDb.dbQueue.write { db in
            var ch1 = PublishingChannel(name: "Medium 1", channelType: .medium)
            try ch1.insert(db)
            var ch2 = PublishingChannel(name: "Twitter 1", channelType: .twitter)
            try ch2.insert(db)
        }

        let medium = try! appDb.dbQueue.read { db in
            try PublishingChannel.filter(Column("channelType") == PublishingChannel.ChannelType.medium.rawValue).fetchAll(db)
        }
        assertEq(medium.count, 1)
        assertEq(medium[0].name, "Medium 1")
    }

    static func testUpdateCredentials() {
        let appDb = try! AppDatabase.makeEmpty()
        let channelId = UUID()

        try! appDb.dbQueue.write { db in
            var channel = PublishingChannel(id: channelId, name: "WP", channelType: .wordpress, credentialsJSON: "{}")
            try channel.insert(db)
        }

        try! appDb.dbQueue.write { db in
            var channel = try PublishingChannel.fetchOne(db, id: channelId)!
            channel.credentialsJSON = "{\"user\":\"admin\",\"password\":\"secret\"}"
            channel.updatedAt = Date()
            try channel.update(db)
        }

        let updated = try! appDb.dbQueue.read { db in
            try PublishingChannel.fetchOne(db, id: channelId)!
        }
        assertTrue(updated.credentialsJSON.contains("admin"))
    }

    static func testDisableChannel() {
        let appDb = try! AppDatabase.makeEmpty()
        let channelId = UUID()

        try! appDb.dbQueue.write { db in
            var channel = PublishingChannel(id: channelId, name: "Twitter", channelType: .twitter, isEnabled: true)
            try channel.insert(db)
        }

        try! appDb.dbQueue.write { db in
            var channel = try PublishingChannel.fetchOne(db, id: channelId)!
            channel.isEnabled = false
            try channel.update(db)
        }

        let updated = try! appDb.dbQueue.read { db in
            try PublishingChannel.fetchOne(db, id: channelId)!
        }
        assertTrue(!updated.isEnabled)
    }
}

// MARK: - Publication Tests

enum PublicationTests {
    static func runAll() {
        testInsertAndFetch()
        testStatusEnum()
        testExportFormatEnum()
        testScheduledPublication()
        testPublishedWithUrl()
        testFailedWithError()
        testFilterByStatus()
        testFilterByChannel()
        print("  PublicationTests: 8/8 passed")
    }

    private static func makePrereqs(in db: Database) -> (projectId: UUID, taskId: UUID, assetId: UUID, channelId: UUID) {
        let projectId = UUID()
        let taskId = UUID()
        let assetId = UUID()
        let channelId = UUID()

        var project = Project(id: projectId, name: "Test", description: "Test")
        try! project.insert(db)
        var task = AgentTask(id: taskId, projectId: projectId, agentType: .contentWriter, title: "Write", description: "Write content")
        try! task.insert(db)
        var asset = GeneratedAsset(id: assetId, projectId: projectId, taskId: taskId, agentType: .contentWriter, assetType: .document, name: "article.md", filePath: "/tmp/article.md")
        try! asset.insert(db)
        var channel = PublishingChannel(id: channelId, name: "Medium", channelType: .medium)
        try! channel.insert(db)

        return (projectId, taskId, assetId, channelId)
    }

    static func testInsertAndFetch() {
        let appDb = try! AppDatabase.makeEmpty()
        let pubId = UUID()

        try! appDb.dbQueue.write { db in
            let prereqs = makePrereqs(in: db)
            var pub = Publication(
                id: pubId,
                assetId: prereqs.assetId,
                projectId: prereqs.projectId,
                channelId: prereqs.channelId,
                status: .scheduled,
                exportFormat: .html
            )
            try pub.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try Publication.fetchOne(db, id: pubId)
        }

        assertTrue(fetched != nil)
        assertEq(fetched!.status, .scheduled)
        assertEq(fetched!.exportFormat, .html)
        assertNil(fetched!.publishedUrl)
        assertNil(fetched!.externalId)
    }

    static func testStatusEnum() {
        let statuses: [Publication.Status] = [.scheduled, .publishing, .published, .failed]
        assertEq(statuses.count, 4)
        assertEq(Publication.Status.scheduled.rawValue, "scheduled")
        assertEq(Publication.Status.published.rawValue, "published")
    }

    static func testExportFormatEnum() {
        let formats: [Publication.ExportFormat] = [.markdown, .html, .plaintext, .pdf]
        assertEq(formats.count, 4)
        assertEq(Publication.ExportFormat.markdown.rawValue, "markdown")
        assertEq(Publication.ExportFormat.pdf.rawValue, "pdf")
    }

    static func testScheduledPublication() {
        let appDb = try! AppDatabase.makeEmpty()
        let futureDate = Date().addingTimeInterval(3600)

        try! appDb.dbQueue.write { db in
            let prereqs = makePrereqs(in: db)
            var pub = Publication(
                assetId: prereqs.assetId,
                projectId: prereqs.projectId,
                channelId: prereqs.channelId,
                status: .scheduled,
                scheduledAt: futureDate
            )
            try pub.insert(db)
        }

        let all = try! appDb.dbQueue.read { db in
            try Publication.fetchAll(db)
        }
        assertEq(all.count, 1)
        assertEq(all[0].status, .scheduled)
        assertTrue(all[0].scheduledAt != nil)
    }

    static func testPublishedWithUrl() {
        let appDb = try! AppDatabase.makeEmpty()
        let pubId = UUID()

        try! appDb.dbQueue.write { db in
            let prereqs = makePrereqs(in: db)
            var pub = Publication(
                id: pubId,
                assetId: prereqs.assetId,
                projectId: prereqs.projectId,
                channelId: prereqs.channelId,
                status: .published,
                externalId: "ext-123",
                publishedUrl: "https://medium.com/@user/article-123",
                publishedAt: Date()
            )
            try pub.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try Publication.fetchOne(db, id: pubId)!
        }
        assertEq(fetched.status, .published)
        assertEq(fetched.externalId, "ext-123")
        assertEq(fetched.publishedUrl, "https://medium.com/@user/article-123")
        assertTrue(fetched.publishedAt != nil)
    }

    static func testFailedWithError() {
        let appDb = try! AppDatabase.makeEmpty()
        let pubId = UUID()

        try! appDb.dbQueue.write { db in
            let prereqs = makePrereqs(in: db)
            var pub = Publication(
                id: pubId,
                assetId: prereqs.assetId,
                projectId: prereqs.projectId,
                channelId: prereqs.channelId,
                status: .failed,
                errorMessage: "401 Unauthorized"
            )
            try pub.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try Publication.fetchOne(db, id: pubId)!
        }
        assertEq(fetched.status, .failed)
        assertEq(fetched.errorMessage, "401 Unauthorized")
    }

    static func testFilterByStatus() {
        let appDb = try! AppDatabase.makeEmpty()

        try! appDb.dbQueue.write { db in
            let prereqs = makePrereqs(in: db)
            var pub1 = Publication(assetId: prereqs.assetId, projectId: prereqs.projectId, channelId: prereqs.channelId, status: .published)
            try pub1.insert(db)
            var pub2 = Publication(assetId: prereqs.assetId, projectId: prereqs.projectId, channelId: prereqs.channelId, status: .failed, errorMessage: "error")
            try pub2.insert(db)
            var pub3 = Publication(assetId: prereqs.assetId, projectId: prereqs.projectId, channelId: prereqs.channelId, status: .published)
            try pub3.insert(db)
        }

        let published = try! appDb.dbQueue.read { db in
            try Publication.filter(Column("status") == Publication.Status.published.rawValue).fetchAll(db)
        }
        assertEq(published.count, 2)
    }

    static func testFilterByChannel() {
        let appDb = try! AppDatabase.makeEmpty()
        let ch1 = UUID()
        let ch2 = UUID()

        try! appDb.dbQueue.write { db in
            let projectId = UUID()
            let taskId = UUID()
            let assetId = UUID()

            var project = Project(id: projectId, name: "Test", description: "Test")
            try project.insert(db)
            var task = AgentTask(id: taskId, projectId: projectId, agentType: .contentWriter, title: "Write", description: "W")
            try task.insert(db)
            var asset = GeneratedAsset(id: assetId, projectId: projectId, taskId: taskId, agentType: .contentWriter, assetType: .document, name: "doc.md", filePath: "/tmp/doc.md")
            try asset.insert(db)
            var channel1 = PublishingChannel(id: ch1, name: "Medium", channelType: .medium)
            try channel1.insert(db)
            var channel2 = PublishingChannel(id: ch2, name: "Twitter", channelType: .twitter)
            try channel2.insert(db)

            var pub1 = Publication(assetId: assetId, projectId: projectId, channelId: ch1, status: .published)
            try pub1.insert(db)
            var pub2 = Publication(assetId: assetId, projectId: projectId, channelId: ch2, status: .published)
            try pub2.insert(db)
            var pub3 = Publication(assetId: assetId, projectId: projectId, channelId: ch1, status: .scheduled)
            try pub3.insert(db)
        }

        let mediumPubs = try! appDb.dbQueue.read { db in
            try Publication.filter(Column("channelId") == ch1).fetchAll(db)
        }
        assertEq(mediumPubs.count, 2)
    }
}
