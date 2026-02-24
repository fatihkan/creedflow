import Foundation
import GRDB
@testable import CreedFlowLib

enum GeneratedAssetTests {
    static func runAll() {
        testInsertAndFetch()
        testDefaultValues()
        testAssetTypeEnum()
        testStatusEnum()
        testVersioningFields()
        testParentAssetLinkage()
        testFilterByProjectId()
        testFilterByStatus()
        testFilterByAssetType()
        testUpdateStatus()
        print("  GeneratedAssetTests: 10/10 passed")
    }

    private static func makeProject(id: UUID = UUID(), in db: Database) throws {
        var project = Project(id: id, name: "Test", description: "Test project")
        try project.insert(db)
    }

    private static func makeTask(id: UUID = UUID(), projectId: UUID, agentType: AgentTask.AgentType = .designer, in db: Database) throws {
        var task = AgentTask(
            id: id, projectId: projectId, agentType: agentType,
            title: "Test task", description: "Test"
        )
        try task.insert(db)
    }

    static func testInsertAndFetch() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()
        let assetId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            try makeTask(id: taskId, projectId: projectId, in: db)
            var asset = GeneratedAsset(
                id: assetId,
                projectId: projectId,
                taskId: taskId,
                agentType: .designer,
                assetType: .design,
                name: "logo.svg",
                assetDescription: "Logo design",
                filePath: "/tmp/logo.svg",
                mimeType: "image/svg+xml",
                fileSize: 2048
            )
            try asset.insert(db)
        }

        let fetched = try! appDb.dbQueue.read { db in
            try GeneratedAsset.fetchOne(db, id: assetId)
        }

        assertTrue(fetched != nil, "should find asset")
        assertEq(fetched!.name, "logo.svg")
        assertEq(fetched!.assetType, .design)
        assertEq(fetched!.mimeType, "image/svg+xml")
        assertEq(fetched!.fileSize, 2048)
        assertEq(fetched!.agentType, .designer)
    }

    static func testDefaultValues() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            try makeTask(id: taskId, projectId: projectId, in: db)
            var asset = GeneratedAsset(
                projectId: projectId, taskId: taskId,
                agentType: .designer, assetType: .image,
                name: "test.png", filePath: "/tmp/test.png"
            )
            try asset.insert(db)
        }

        let all = try! appDb.dbQueue.read { db in
            try GeneratedAsset.fetchAll(db)
        }
        assertEq(all.count, 1)
        assertEq(all[0].status, .generated)
        assertEq(all[0].version, 1)
        assertNil(all[0].thumbnailPath)
        assertNil(all[0].checksum)
        assertNil(all[0].parentAssetId)
        assertNil(all[0].reviewTaskId)
    }

    static func testAssetTypeEnum() {
        let types: [GeneratedAsset.AssetType] = [.image, .video, .audio, .design, .document]
        assertEq(types.count, 5)
        assertEq(GeneratedAsset.AssetType.image.rawValue, "image")
        assertEq(GeneratedAsset.AssetType.video.rawValue, "video")
        assertEq(GeneratedAsset.AssetType.audio.rawValue, "audio")
        assertEq(GeneratedAsset.AssetType.design.rawValue, "design")
        assertEq(GeneratedAsset.AssetType.document.rawValue, "document")
    }

    static func testStatusEnum() {
        let statuses: [GeneratedAsset.Status] = [.generated, .reviewed, .approved, .rejected]
        assertEq(statuses.count, 4)
        assertEq(GeneratedAsset.Status.generated.rawValue, "generated")
        assertEq(GeneratedAsset.Status.approved.rawValue, "approved")
    }

    static func testVersioningFields() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()
        let parentId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            try makeTask(id: taskId, projectId: projectId, in: db)

            // Create parent asset first (parentAssetId has FK to generatedAsset)
            var parent = GeneratedAsset(
                id: parentId, projectId: projectId, taskId: taskId,
                agentType: .imageGenerator, assetType: .image,
                name: "hero.png", filePath: "/tmp/hero_v1.png",
                version: 1
            )
            try parent.insert(db)

            var asset = GeneratedAsset(
                projectId: projectId, taskId: taskId,
                agentType: .imageGenerator, assetType: .image,
                name: "hero.png", filePath: "/tmp/hero.png",
                version: 3,
                thumbnailPath: "/tmp/hero_thumb.png",
                checksum: "abc123def456",
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
        assertEq(all[0].thumbnailPath, "/tmp/hero_thumb.png")
        assertEq(all[0].checksum, "abc123def456")
        assertEq(all[0].parentAssetId, parentId)
    }

    static func testParentAssetLinkage() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()
        let v1Id = UUID()
        let v2Id = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            try makeTask(id: taskId, projectId: projectId, in: db)

            var v1 = GeneratedAsset(
                id: v1Id, projectId: projectId, taskId: taskId,
                agentType: .designer, assetType: .design,
                name: "icon.svg", filePath: "/tmp/icon_v1.svg",
                version: 1
            )
            try v1.insert(db)

            var v2 = GeneratedAsset(
                id: v2Id, projectId: projectId, taskId: taskId,
                agentType: .designer, assetType: .design,
                name: "icon.svg", filePath: "/tmp/icon_v2.svg",
                version: 2, parentAssetId: v1Id
            )
            try v2.insert(db)
        }

        let v2 = try! appDb.dbQueue.read { db in
            try GeneratedAsset.fetchOne(db, id: v2Id)
        }!
        assertEq(v2.parentAssetId, v1Id)
        assertEq(v2.version, 2)
    }

    static func testFilterByProjectId() {
        let appDb = try! AppDatabase.makeEmpty()
        let p1 = UUID(), p2 = UUID()
        let t1 = UUID(), t2 = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: p1, in: db)
            try makeProject(id: p2, in: db)
            try makeTask(id: t1, projectId: p1, in: db)
            try makeTask(id: t2, projectId: p2, in: db)

            var a1 = GeneratedAsset(projectId: p1, taskId: t1, agentType: .designer, assetType: .image, name: "a.png", filePath: "/tmp/a.png")
            try a1.insert(db)
            var a2 = GeneratedAsset(projectId: p2, taskId: t2, agentType: .designer, assetType: .image, name: "b.png", filePath: "/tmp/b.png")
            try a2.insert(db)
        }

        let assets = try! appDb.dbQueue.read { db in
            try GeneratedAsset.filter(Column("projectId") == p1).fetchAll(db)
        }
        assertEq(assets.count, 1)
        assertEq(assets[0].name, "a.png")
    }

    static func testFilterByStatus() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            try makeTask(id: taskId, projectId: projectId, in: db)

            var a1 = GeneratedAsset(projectId: projectId, taskId: taskId, agentType: .designer, assetType: .image, name: "a.png", filePath: "/tmp/a.png", status: .approved)
            try a1.insert(db)
            var a2 = GeneratedAsset(projectId: projectId, taskId: taskId, agentType: .designer, assetType: .image, name: "b.png", filePath: "/tmp/b.png", status: .rejected)
            try a2.insert(db)
        }

        let approved = try! appDb.dbQueue.read { db in
            try GeneratedAsset.filter(Column("status") == GeneratedAsset.Status.approved.rawValue).fetchAll(db)
        }
        assertEq(approved.count, 1)
        assertEq(approved[0].name, "a.png")
    }

    static func testFilterByAssetType() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            try makeTask(id: taskId, projectId: projectId, in: db)

            var img = GeneratedAsset(projectId: projectId, taskId: taskId, agentType: .imageGenerator, assetType: .image, name: "photo.png", filePath: "/tmp/photo.png")
            try img.insert(db)
            var doc = GeneratedAsset(projectId: projectId, taskId: taskId, agentType: .contentWriter, assetType: .document, name: "readme.md", filePath: "/tmp/readme.md")
            try doc.insert(db)
        }

        let docs = try! appDb.dbQueue.read { db in
            try GeneratedAsset.filter(Column("assetType") == GeneratedAsset.AssetType.document.rawValue).fetchAll(db)
        }
        assertEq(docs.count, 1)
        assertEq(docs[0].name, "readme.md")
    }

    static func testUpdateStatus() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()
        let assetId = UUID()

        try! appDb.dbQueue.write { db in
            try makeProject(id: projectId, in: db)
            try makeTask(id: taskId, projectId: projectId, in: db)
            var asset = GeneratedAsset(
                id: assetId, projectId: projectId, taskId: taskId,
                agentType: .designer, assetType: .design,
                name: "banner.svg", filePath: "/tmp/banner.svg"
            )
            try asset.insert(db)
        }

        try! appDb.dbQueue.write { db in
            var asset = try GeneratedAsset.fetchOne(db, id: assetId)!
            asset.status = .approved
            asset.updatedAt = Date()
            try asset.update(db)
        }

        let updated = try! appDb.dbQueue.read { db in
            try GeneratedAsset.fetchOne(db, id: assetId)!
        }
        assertEq(updated.status, .approved)
    }
}
