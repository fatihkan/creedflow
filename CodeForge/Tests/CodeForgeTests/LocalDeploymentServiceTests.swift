import Foundation
import GRDB
@testable import CodeForgeLib

enum LocalDeploymentServiceTests {
    static func runAll() {
        testDetectDockerfile()
        testDetectDockerCompose()
        testDetectNodeProject()
        testDetectGoProject()
        testDetectSwiftProject()
        testDetectPythonProject()
        testDetectRustProject()
        testDetectMakefile()
        testDetectFallback()
        testDetectPriority()
        testStopUpdatesDeploymentStatus()
        print("  LocalDeploymentServiceTests: 11/11 passed")
    }

    // MARK: - Helpers

    /// Bridge async actor calls to synchronous test context.
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

    /// Create a temporary directory, returning its path. Caller must clean up.
    private static func makeTempDir() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeForgeTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// Remove a temporary directory.
    private static func removeTempDir(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Create an empty file at the given path.
    private static func touch(_ path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }

    /// Detect project type using a real LocalDeploymentService actor.
    private static func detect(at dir: String) -> LocalDeploymentService.DetectedProject {
        let dbQueue = try! DatabaseQueue()
        let service = LocalDeploymentService(dbQueue: dbQueue)
        return try! runBlocking { await service.detectProjectType(at: dir) }
    }

    // MARK: - Detection Tests

    static func testDetectDockerfile() {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }
        touch("\(dir)/Dockerfile")

        let result = detect(at: dir)
        assertEq(result.method, .docker)
    }

    static func testDetectDockerCompose() {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }
        touch("\(dir)/docker-compose.yml")

        let result = detect(at: dir)
        assertEq(result.method, .dockerCompose)
    }

    static func testDetectNodeProject() {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }
        touch("\(dir)/package.json")

        let result = detect(at: dir)
        assertEq(result.method, .direct)
        assertEq(result.buildCommand, "npm install")
        assertEq(result.runCommand, "npm start")
    }

    static func testDetectGoProject() {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }
        touch("\(dir)/go.mod")

        let result = detect(at: dir)
        assertEq(result.method, .direct)
        assertEq(result.buildCommand, "go build -o app .")
        assertEq(result.runCommand, "./app")
    }

    static func testDetectSwiftProject() {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }
        touch("\(dir)/Package.swift")

        let result = detect(at: dir)
        assertEq(result.method, .direct)
        assertEq(result.buildCommand, "swift build")
        assertEq(result.runCommand, "swift run")
    }

    static func testDetectPythonProject() {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }
        touch("\(dir)/requirements.txt")

        let result = detect(at: dir)
        assertEq(result.method, .direct)
        assertEq(result.buildCommand, "pip install -r requirements.txt")
        assertEq(result.runCommand, "python main.py")
    }

    static func testDetectRustProject() {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }
        touch("\(dir)/Cargo.toml")

        let result = detect(at: dir)
        assertEq(result.method, .direct)
        assertEq(result.buildCommand, "cargo build --release")
        assertEq(result.runCommand, "cargo run --release")
    }

    static func testDetectMakefile() {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }
        touch("\(dir)/Makefile")

        let result = detect(at: dir)
        assertEq(result.method, .direct)
        assertEq(result.buildCommand, "")
        assertEq(result.runCommand, "make run")
    }

    static func testDetectFallback() {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }
        // Empty directory — no recognized project files

        let result = detect(at: dir)
        assertEq(result.method, .direct)
        assertEq(result.buildCommand, "")
        assertTrue(result.runCommand.contains("No recognized project type"))
    }

    static func testDetectPriority() {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }
        // Both Dockerfile and package.json — docker-compose.yml checked first,
        // then Dockerfile, so Dockerfile wins over package.json
        touch("\(dir)/Dockerfile")
        touch("\(dir)/package.json")

        let result = detect(at: dir)
        assertEq(result.method, .docker)
    }

    // MARK: - Stop Test

    static func testStopUpdatesDeploymentStatus() {
        let appDb = try! AppDatabase.makeEmpty()
        let projectId = UUID()
        let deploymentId = UUID()

        // Insert project and a "running" deployment (no containerId/processId to avoid shell commands)
        try! appDb.dbQueue.write { db in
            var project = Project(id: projectId, name: "StopTest", description: "Test")
            try project.insert(db)
            var deployment = Deployment(
                id: deploymentId,
                projectId: projectId,
                status: .success,
                version: "1.0.0"
            )
            try deployment.insert(db)
        }

        let service = LocalDeploymentService(dbQueue: appDb.dbQueue)

        let deployment = try! appDb.dbQueue.read { db in
            try Deployment.fetchOne(db, key: deploymentId)!
        }

        try! runBlocking { try await service.stop(deployment: deployment) }

        let updated = try! appDb.dbQueue.read { db in
            try Deployment.fetchOne(db, key: deploymentId)!
        }

        assertEq(updated.status, .rolledBack)
        assertTrue(updated.completedAt != nil, "completedAt should be set")
        assertTrue(updated.logs?.contains("Stopped by user") == true, "logs should contain stop message")
    }
}
