import Foundation
import GRDB
@testable import CreedFlowLib

enum ProjectBundleTests {
    static func runAll() {
        print("ProjectBundleTests")
        testExportCreatesValidBundle()
        testImportCreatesProjectWithNewUUIDs()
        testRoundTrip()
        testImportWithFiles()
        testInvalidBundleMissingManifest()
        print("  All ProjectBundleTests passed (\(passed)/\(passed))")
    }

    private static var passed = 0

    private static func assert(_ condition: Bool, _ msg: String, line: Int = #line) {
        if condition {
            passed += 1
        } else {
            fatalError("  FAIL (line \(line)): \(msg)")
        }
    }

    // MARK: - Helpers

    private static func makeInMemoryDB() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue(configuration: {
            var config = Configuration()
            config.foreignKeysEnabled = true
            return config
        }())
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE project (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    techStack TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL DEFAULT 'planning',
                    directoryPath TEXT NOT NULL DEFAULT '',
                    projectType TEXT NOT NULL DEFAULT 'software',
                    stagingPrNumber INTEGER,
                    completedAt TEXT,
                    telegramChatId INTEGER,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE feature (
                    id TEXT PRIMARY KEY,
                    projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    priority INTEGER NOT NULL DEFAULT 0,
                    status TEXT NOT NULL DEFAULT 'pending',
                    integrationPrNumber INTEGER,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE agentTask (
                    id TEXT PRIMARY KEY,
                    projectId TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
                    featureId TEXT REFERENCES feature(id) ON DELETE SET NULL,
                    agentType TEXT NOT NULL,
                    title TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    priority INTEGER NOT NULL DEFAULT 0,
                    status TEXT NOT NULL DEFAULT 'queued',
                    result TEXT,
                    errorMessage TEXT,
                    retryCount INTEGER NOT NULL DEFAULT 0,
                    maxRetries INTEGER NOT NULL DEFAULT 3,
                    sessionId TEXT,
                    branchName TEXT,
                    prNumber INTEGER,
                    costUSD REAL,
                    durationMs INTEGER,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL,
                    startedAt TEXT,
                    completedAt TEXT,
                    backend TEXT,
                    promptChainId TEXT,
                    revisionPrompt TEXT,
                    skillPersona TEXT,
                    archivedAt TEXT
                )
            """)
            try db.execute(sql: """
                CREATE TABLE taskDependency (
                    taskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
                    dependsOnTaskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
                    PRIMARY KEY (taskId, dependsOnTaskId)
                )
            """)
            try db.execute(sql: """
                CREATE TABLE review (
                    id TEXT PRIMARY KEY,
                    taskId TEXT NOT NULL REFERENCES agentTask(id) ON DELETE CASCADE,
                    score REAL NOT NULL DEFAULT 0,
                    verdict TEXT NOT NULL DEFAULT 'fail',
                    summary TEXT NOT NULL DEFAULT '',
                    issues TEXT,
                    suggestions TEXT,
                    securityNotes TEXT,
                    sessionId TEXT,
                    costUSD REAL,
                    isApproved INTEGER NOT NULL DEFAULT 0,
                    createdAt TEXT NOT NULL
                )
            """)
        }
        return dbQueue
    }

    private static func seedProject(dbQueue: DatabaseQueue) throws -> (Project, Feature, AgentTask, AgentTask, Review) {
        let projectId = UUID()
        let featureId = UUID()
        let task1Id = UUID()
        let task2Id = UUID()
        let reviewId = UUID()

        // Create a temp directory for the project
        let fm = FileManager.default
        let projectDir = fm.temporaryDirectory.appendingPathComponent("creedflow-test-project-\(projectId.uuidString)")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Write a test file
        try "Hello World".write(to: projectDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try dbQueue.write { db in
            var project = Project(
                id: projectId,
                name: "TestProject",
                description: "A test project",
                techStack: "Swift",
                directoryPath: projectDir.path
            )
            try project.insert(db)

            var feature = Feature(
                id: featureId,
                projectId: projectId,
                name: "Feature A",
                description: "First feature"
            )
            try feature.insert(db)

            var task1 = AgentTask(
                id: task1Id,
                projectId: projectId,
                featureId: featureId,
                agentType: .coder,
                title: "Write code",
                description: "Implement feature A",
                priority: 9,
                status: .passed
            )
            try task1.insert(db)

            var task2 = AgentTask(
                id: task2Id,
                projectId: projectId,
                featureId: featureId,
                agentType: .tester,
                title: "Test code",
                description: "Test feature A",
                priority: 7,
                status: .queued
            )
            try task2.insert(db)

            var dep = TaskDependency(taskId: task2Id, dependsOnTaskId: task1Id)
            try dep.insert(db)

            var review = Review(
                id: reviewId,
                taskId: task1Id,
                score: 8.5,
                verdict: .pass,
                summary: "Good code"
            )
            try review.insert(db)
        }

        let project = try dbQueue.read { try Project.fetchOne($0, id: projectId)! }
        let feature = try dbQueue.read { try Feature.fetchOne($0, id: featureId)! }
        let task1 = try dbQueue.read { try AgentTask.fetchOne($0, id: task1Id)! }
        let task2 = try dbQueue.read { try AgentTask.fetchOne($0, id: task2Id)! }
        let review = try dbQueue.read { try Review.fetchOne($0, id: reviewId)! }
        return (project, feature, task1, task2, review)
    }

    // MARK: - Tests

    private static func testExportCreatesValidBundle() {
        do {
            let dbQueue = try makeInMemoryDB()
            let (project, _, _, _, _) = try seedProject(dbQueue: dbQueue)

            let fm = FileManager.default
            let outputURL = fm.temporaryDirectory.appendingPathComponent("test-export-\(UUID().uuidString).creedflow")
            defer { try? fm.removeItem(at: outputURL) }

            let service = ProjectBundleService()
            try syncCall { try await service.exportBundle(project: project, dbQueue: dbQueue, to: outputURL) }

            assert(fm.fileExists(atPath: outputURL.path), "Bundle file should exist")

            // Unzip and verify contents
            let verifyDir = fm.temporaryDirectory.appendingPathComponent("verify-\(UUID().uuidString)")
            try fm.createDirectory(at: verifyDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: verifyDir) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", outputURL.path, "-d", verifyDir.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            let bundleDir = verifyDir.appendingPathComponent(project.name)
            assert(fm.fileExists(atPath: bundleDir.appendingPathComponent("manifest.json").path), "manifest.json should exist")
            assert(fm.fileExists(atPath: bundleDir.appendingPathComponent("project.json").path), "project.json should exist")
            assert(fm.fileExists(atPath: bundleDir.appendingPathComponent("features.json").path), "features.json should exist")
            assert(fm.fileExists(atPath: bundleDir.appendingPathComponent("tasks.json").path), "tasks.json should exist")
            assert(fm.fileExists(atPath: bundleDir.appendingPathComponent("dependencies.json").path), "dependencies.json should exist")
            assert(fm.fileExists(atPath: bundleDir.appendingPathComponent("reviews.json").path), "reviews.json should exist")

            print("  ✓ testExportCreatesValidBundle")
        } catch {
            fatalError("  FAIL: testExportCreatesValidBundle - \(error)")
        }
    }

    private static func testImportCreatesProjectWithNewUUIDs() {
        do {
            let dbQueue = try makeInMemoryDB()
            let (project, _, task1, _, _) = try seedProject(dbQueue: dbQueue)

            let fm = FileManager.default
            let bundlePath = fm.temporaryDirectory.appendingPathComponent("test-import-\(UUID().uuidString).creedflow")
            defer { try? fm.removeItem(at: bundlePath) }

            let service = ProjectBundleService()
            try syncCall { try await service.exportBundle(project: project, dbQueue: dbQueue, to: bundlePath) }

            let imported = try syncCall { try await service.importBundle(from: bundlePath, dbQueue: dbQueue) }

            assert(imported.id != project.id, "Imported project should have new UUID")
            assert(imported.name == project.name, "Imported project should have same name")
            assert(imported.description == project.description, "Imported project should have same description")

            // Verify tasks were created with new UUIDs
            let importedTasks = try dbQueue.read { db in
                try AgentTask
                    .filter(Column("projectId") == imported.id)
                    .fetchAll(db)
            }
            assert(importedTasks.count == 2, "Should have 2 imported tasks, got \(importedTasks.count)")
            assert(!importedTasks.contains(where: { $0.id == task1.id }), "Imported tasks should have new UUIDs")

            print("  ✓ testImportCreatesProjectWithNewUUIDs")
        } catch {
            fatalError("  FAIL: testImportCreatesProjectWithNewUUIDs - \(error)")
        }
    }

    private static func testRoundTrip() {
        do {
            let dbQueue = try makeInMemoryDB()
            let (project, _, _, _, _) = try seedProject(dbQueue: dbQueue)

            let fm = FileManager.default
            let bundlePath = fm.temporaryDirectory.appendingPathComponent("test-roundtrip-\(UUID().uuidString).creedflow")
            defer { try? fm.removeItem(at: bundlePath) }

            let service = ProjectBundleService()
            try syncCall { try await service.exportBundle(project: project, dbQueue: dbQueue, to: bundlePath) }
            let imported = try syncCall { try await service.importBundle(from: bundlePath, dbQueue: dbQueue) }

            // Verify features
            let importedFeatures = try dbQueue.read { db in
                try Feature.filter(Column("projectId") == imported.id).fetchAll(db)
            }
            assert(importedFeatures.count == 1, "Should have 1 feature, got \(importedFeatures.count)")
            assert(importedFeatures[0].name == "Feature A", "Feature name should match")

            // Verify dependencies
            let importedTasks = try dbQueue.read { db in
                try AgentTask.filter(Column("projectId") == imported.id).fetchAll(db)
            }
            let testerTask = importedTasks.first { $0.agentType == .tester }!
            let deps = try dbQueue.read { db in
                try TaskDependency.filter(Column("taskId") == testerTask.id).fetchAll(db)
            }
            assert(deps.count == 1, "Tester task should have 1 dependency, got \(deps.count)")

            let coderTask = importedTasks.first { $0.agentType == .coder }!
            assert(deps[0].dependsOnTaskId == coderTask.id, "Dependency should point to coder task")

            // Verify reviews
            let importedReviews = try dbQueue.read { db in
                try Review.filter(Column("taskId") == coderTask.id).fetchAll(db)
            }
            assert(importedReviews.count == 1, "Should have 1 review, got \(importedReviews.count)")
            assert(importedReviews[0].score == 8.5, "Review score should match")
            assert(importedReviews[0].summary == "Good code", "Review summary should match")

            print("  ✓ testRoundTrip")
        } catch {
            fatalError("  FAIL: testRoundTrip - \(error)")
        }
    }

    private static func testImportWithFiles() {
        do {
            let dbQueue = try makeInMemoryDB()
            let (project, _, _, _, _) = try seedProject(dbQueue: dbQueue)

            let fm = FileManager.default
            let bundlePath = fm.temporaryDirectory.appendingPathComponent("test-files-\(UUID().uuidString).creedflow")
            defer { try? fm.removeItem(at: bundlePath) }

            let service = ProjectBundleService()
            try syncCall { try await service.exportBundle(project: project, dbQueue: dbQueue, to: bundlePath) }
            let imported = try syncCall { try await service.importBundle(from: bundlePath, dbQueue: dbQueue) }

            // Verify the README.md was copied
            let importedDir = URL(fileURLWithPath: imported.directoryPath)
            let readmePath = importedDir.appendingPathComponent("README.md")
            assert(fm.fileExists(atPath: readmePath.path), "README.md should be copied to imported project directory")

            let content = try String(contentsOf: readmePath)
            assert(content == "Hello World", "README.md content should match")

            // Cleanup imported project dir
            try? fm.removeItem(at: importedDir)

            print("  ✓ testImportWithFiles")
        } catch {
            fatalError("  FAIL: testImportWithFiles - \(error)")
        }
    }

    private static func testInvalidBundleMissingManifest() {
        do {
            let dbQueue = try makeInMemoryDB()
            let fm = FileManager.default

            // Create a fake ZIP without manifest.json
            let tempDir = fm.temporaryDirectory.appendingPathComponent("fake-bundle-\(UUID().uuidString)")
            let innerDir = tempDir.appendingPathComponent("FakeProject")
            try fm.createDirectory(at: innerDir, withIntermediateDirectories: true)
            try "{}".write(to: innerDir.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)

            let zipPath = fm.temporaryDirectory.appendingPathComponent("fake-\(UUID().uuidString).creedflow")
            defer {
                try? fm.removeItem(at: tempDir)
                try? fm.removeItem(at: zipPath)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-r", zipPath.path, "FakeProject"]
            process.currentDirectoryURL = tempDir
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            let service = ProjectBundleService()
            var didThrow = false
            do {
                _ = try syncCall { try await service.importBundle(from: zipPath, dbQueue: dbQueue) }
            } catch {
                didThrow = true
                assert(error.localizedDescription.contains("manifest"), "Error should mention manifest, got: \(error.localizedDescription)")
            }
            assert(didThrow, "Import should throw for missing manifest")

            print("  ✓ testInvalidBundleMissingManifest")
        } catch {
            fatalError("  FAIL: testInvalidBundleMissingManifest - \(error)")
        }
    }

    // Helper to run async code synchronously in tests
    @discardableResult
    private static func syncCall<T>(_ block: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>!
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
        return try result.get()
    }
}
