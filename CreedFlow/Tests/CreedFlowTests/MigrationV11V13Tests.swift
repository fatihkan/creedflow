import Foundation
import GRDB
@testable import CreedFlowLib

enum MigrationV11V13Tests {
    static func runAll() {
        testGeneratedAssetTableExists()
        testGeneratedAssetVersioningColumnsExist()
        testPublishingChannelTableExists()
        testPublicationTableExists()
        testPublicationForeignKeys()
        print("  MigrationV11V13Tests: 5/5 passed")
    }

    static func testGeneratedAssetTableExists() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()
        let assetId = UUID()

        try! appDb.dbQueue.write { db in
            var project = Project(id: projectId, name: "M11", description: "Test")
            try project.insert(db)
            var task = AgentTask(id: taskId, projectId: projectId, agentType: .designer, title: "T", description: "D")
            try task.insert(db)
            var asset = GeneratedAsset(
                id: assetId, projectId: projectId, taskId: taskId,
                agentType: .designer, assetType: .image,
                name: "test.png", filePath: "/tmp/test.png"
            )
            try asset.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try GeneratedAsset.fetchOne(db, id: assetId)
        }
        assertTrue(fetched != nil, "generatedAsset table should exist from v11")
    }

    static func testGeneratedAssetVersioningColumnsExist() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()
        let parentId = UUID()

        try! appDb.dbQueue.write { db in
            var project = Project(id: projectId, name: "M12", description: "Test")
            try project.insert(db)
            var task = AgentTask(id: taskId, projectId: projectId, agentType: .designer, title: "T", description: "D")
            try task.insert(db)

            // Create parent asset first (parentAssetId has FK to generatedAsset)
            var parent = GeneratedAsset(
                id: parentId, projectId: projectId, taskId: taskId,
                agentType: .designer, assetType: .design,
                name: "versioned.svg", filePath: "/tmp/v_parent.svg",
                version: 1
            )
            try parent.insert(db)

            // Insert with all v12 columns
            var asset = GeneratedAsset(
                projectId: projectId, taskId: taskId,
                agentType: .designer, assetType: .design,
                name: "versioned.svg", filePath: "/tmp/v.svg",
                version: 3,
                thumbnailPath: "/tmp/thumb.png",
                checksum: "abc123",
                parentAssetId: parentId
            )
            try asset.insert(db)
        }

        let all = try! appDb.dbQueue.read { db in
            try GeneratedAsset
                .filter(Column("version") == 3)
                .fetchAll(db)
        }
        assertEq(all.count, 1)
        assertEq(all[0].version, 3)
        assertEq(all[0].thumbnailPath, "/tmp/thumb.png")
        assertEq(all[0].checksum, "abc123")
        assertEq(all[0].parentAssetId, parentId)
    }

    static func testPublishingChannelTableExists() {
        let appDb = try! AppDatabase.makeEmpty()
        let channelId = UUID()

        try! appDb.dbQueue.write { db in
            var channel = PublishingChannel(
                id: channelId, name: "Test Medium",
                channelType: .medium, credentialsJSON: "{\"token\":\"test\"}"
            )
            try channel.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try PublishingChannel.fetchOne(db, id: channelId)
        }
        assertTrue(fetched != nil, "publishingChannel table should exist from v13")
        assertEq(fetched!.channelType, .medium)
    }

    static func testPublicationTableExists() {
        let appDb = try! AppDatabase.makeEmpty()
        let pubId = UUID()

        try! appDb.dbQueue.write { db in
            // Create all prerequisite records
            let projectId = UUID()
            let taskId = UUID()
            let assetId = UUID()
            let channelId = UUID()

            var project = Project(id: projectId, name: "PubTest", description: "Test")
            try project.insert(db)
            var task = AgentTask(id: taskId, projectId: projectId, agentType: .contentWriter, title: "Write", description: "W")
            try task.insert(db)
            var asset = GeneratedAsset(id: assetId, projectId: projectId, taskId: taskId, agentType: .contentWriter, assetType: .document, name: "article.md", filePath: "/tmp/article.md")
            try asset.insert(db)
            var channel = PublishingChannel(id: channelId, name: "Medium", channelType: .medium)
            try channel.insert(db)

            var pub = Publication(
                id: pubId, assetId: assetId, projectId: projectId,
                channelId: channelId, status: .published,
                externalId: "ext-1", publishedUrl: "https://example.com/1",
                exportFormat: .html
            )
            try pub.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try Publication.fetchOne(db, id: pubId)
        }
        assertTrue(fetched != nil, "publication table should exist from v13")
        assertEq(fetched!.status, .published)
        assertEq(fetched!.exportFormat, .html)
    }

    static func testPublicationForeignKeys() {
        let appDb = try! AppDatabase.makeEmpty()

        // Verify that publication records with valid foreign keys work
        try! appDb.dbQueue.write { db in
            let projectId = UUID()
            let taskId = UUID()
            let assetId = UUID()
            let channelId = UUID()

            var project = Project(id: projectId, name: "FKTest", description: "Test")
            try project.insert(db)
            var task = AgentTask(id: taskId, projectId: projectId, agentType: .publisher, title: "Publish", description: "P")
            try task.insert(db)
            var asset = GeneratedAsset(id: assetId, projectId: projectId, taskId: taskId, agentType: .contentWriter, assetType: .document, name: "doc.md", filePath: "/tmp/doc.md")
            try asset.insert(db)
            var channel = PublishingChannel(id: channelId, name: "WP", channelType: .wordpress)
            try channel.insert(db)

            // Insert 3 publications for same asset/channel combo
            for status in [Publication.Status.scheduled, .publishing, .published] {
                var pub = Publication(assetId: assetId, projectId: projectId, channelId: channelId, status: status)
                try pub.insert(db)
            }
        }

        let count = try! appDb.dbQueue.read { db in
            try Publication.fetchCount(db)
        }
        assertEq(count, 3)
    }
}
