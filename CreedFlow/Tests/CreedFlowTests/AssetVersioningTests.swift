import Foundation
import GRDB
@testable import CreedFlowLib

enum AssetVersioningTests {
    static func runAll() {
        testCreateVersionIncrementsNumber()
        testCreateVersionSetsParentId()
        testCreateVersionComputesChecksum()
        testVersionHistoryReturnsOrdered()
        testVersionHistoryEmptyForUnknownId()
        testCreateVersionThrowsForMissingAsset()
        testChecksumReturnsNilForMissingFile()
        testChecksumConsistentForSameContent()
        testMultipleVersionsChain()
        print("  AssetVersioningTests: 9/9 passed")
    }

    // MARK: - Helpers

    private static func runBlocking<T>(_ block: @Sendable @escaping () async throws -> T) throws -> T {
        var result: Result<T, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let value = try await block()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result!.get()
    }

    private static func makeTempFile(_ content: String) -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("creedflow-ver-\(UUID().uuidString).txt").path
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private static func setupDb() -> (AppDatabase, UUID, UUID, UUID) {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()
        let assetId = UUID()

        try! appDb.dbQueue.write { db in
            var project = Project(id: projectId, name: "VersionTest", description: "Test")
            try project.insert(db)
            var task = AgentTask(id: taskId, projectId: projectId, agentType: .designer, title: "Design", description: "Design task")
            try task.insert(db)
            var asset = GeneratedAsset(
                id: assetId, projectId: projectId, taskId: taskId,
                agentType: .designer, assetType: .design,
                name: "icon.svg", filePath: "/tmp/icon_v1.svg",
                version: 1
            )
            try asset.insert(db)
        }
        return (appDb, projectId, taskId, assetId)
    }

    // MARK: - Tests

    static func testCreateVersionIncrementsNumber() {
        let (appDb, _, taskId, assetId) = setupDb()
        let newPath = makeTempFile("version 2 content")
        defer { try? FileManager.default.removeItem(atPath: newPath) }

        let task = try! appDb.dbQueue.read { db in try AgentTask.fetchOne(db, id: taskId)! }
        let service = AssetVersioningService(dbQueue: appDb.dbQueue)
        let v2 = try! runBlocking { try await service.createVersion(of: assetId, newFilePath: newPath, task: task) }

        assertEq(v2.version, 2)
        assertEq(v2.name, "icon.svg")
    }

    static func testCreateVersionSetsParentId() {
        let (appDb, _, taskId, assetId) = setupDb()
        let newPath = makeTempFile("v2")
        defer { try? FileManager.default.removeItem(atPath: newPath) }

        let task = try! appDb.dbQueue.read { db in try AgentTask.fetchOne(db, id: taskId)! }
        let service = AssetVersioningService(dbQueue: appDb.dbQueue)
        let v2 = try! runBlocking { try await service.createVersion(of: assetId, newFilePath: newPath, task: task) }

        assertEq(v2.parentAssetId, assetId)
    }

    static func testCreateVersionComputesChecksum() {
        let (appDb, _, taskId, assetId) = setupDb()
        let newPath = makeTempFile("checksum test content")
        defer { try? FileManager.default.removeItem(atPath: newPath) }

        let task = try! appDb.dbQueue.read { db in try AgentTask.fetchOne(db, id: taskId)! }
        let service = AssetVersioningService(dbQueue: appDb.dbQueue)
        let v2 = try! runBlocking { try await service.createVersion(of: assetId, newFilePath: newPath, task: task) }

        assertTrue(v2.checksum != nil, "checksum should be computed")
        assertTrue(v2.checksum!.count == 64, "SHA256 hex should be 64 chars")
    }

    static func testVersionHistoryReturnsOrdered() {
        let (appDb, projectId, taskId, assetId) = setupDb()

        // Insert v2 and v3 manually
        try! appDb.dbQueue.write { db in
            var v2 = GeneratedAsset(
                projectId: projectId, taskId: taskId,
                agentType: .designer, assetType: .design,
                name: "icon.svg", filePath: "/tmp/icon_v2.svg",
                version: 2, parentAssetId: assetId
            )
            try v2.insert(db)
            var v3 = GeneratedAsset(
                projectId: projectId, taskId: taskId,
                agentType: .designer, assetType: .design,
                name: "icon.svg", filePath: "/tmp/icon_v3.svg",
                version: 3, parentAssetId: v2.id
            )
            try v3.insert(db)
        }

        let service = AssetVersioningService(dbQueue: appDb.dbQueue)
        let history = try! runBlocking { try await service.versionHistory(for: assetId) }

        assertEq(history.count, 3)
        assertEq(history[0].version, 1)
        assertEq(history[1].version, 2)
        assertEq(history[2].version, 3)
    }

    static func testVersionHistoryEmptyForUnknownId() {
        let appDb = try! AppDatabase.makeEmpty()
        let service = AssetVersioningService(dbQueue: appDb.dbQueue)
        let history = try! runBlocking { try await service.versionHistory(for: UUID()) }
        assertTrue(history.isEmpty)
    }

    static func testCreateVersionThrowsForMissingAsset() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let taskId = UUID()

        try! appDb.dbQueue.write { db in
            var project = Project(id: projectId, name: "Test", description: "Test")
            try project.insert(db)
            var task = AgentTask(id: taskId, projectId: projectId, agentType: .designer, title: "T", description: "T")
            try task.insert(db)
        }

        let task = try! appDb.dbQueue.read { db in try AgentTask.fetchOne(db, id: taskId)! }
        let service = AssetVersioningService(dbQueue: appDb.dbQueue)

        do {
            _ = try runBlocking { try await service.createVersion(of: UUID(), newFilePath: "/tmp/fake.txt", task: task) }
            fatalError("Expected AssetVersionError.assetNotFound")
        } catch {
            assertTrue(error is AssetVersionError)
        }
    }

    static func testChecksumReturnsNilForMissingFile() {
        let checksum = AssetVersioningService.computeChecksum(filePath: "/nonexistent/file.txt")
        assertNil(checksum)
    }

    static func testChecksumConsistentForSameContent() {
        let content = "Hello, CreedFlow!"
        let path1 = makeTempFile(content)
        let path2 = makeTempFile(content)
        defer {
            try? FileManager.default.removeItem(atPath: path1)
            try? FileManager.default.removeItem(atPath: path2)
        }

        let c1 = AssetVersioningService.computeChecksum(filePath: path1)
        let c2 = AssetVersioningService.computeChecksum(filePath: path2)
        assertTrue(c1 != nil)
        assertEq(c1!, c2!)
    }

    static func testMultipleVersionsChain() {
        let (appDb, _, taskId, assetId) = setupDb()
        let task = try! appDb.dbQueue.read { db in try AgentTask.fetchOne(db, id: taskId)! }
        let service = AssetVersioningService(dbQueue: appDb.dbQueue)

        // Create v2 from original
        let path2 = makeTempFile("v2 content")
        defer { try? FileManager.default.removeItem(atPath: path2) }
        let v2 = try! runBlocking { try await service.createVersion(of: assetId, newFilePath: path2, task: task) }
        assertEq(v2.version, 2)
        assertEq(v2.parentAssetId, assetId)

        // Create v3 from v2 (chained from the new version)
        let path3 = makeTempFile("v3 content")
        defer { try? FileManager.default.removeItem(atPath: path3) }
        let v3 = try! runBlocking { try await service.createVersion(of: v2.id, newFilePath: path3, task: task) }
        assertEq(v3.version, 3)
        assertEq(v3.parentAssetId, v2.id)
    }
}
