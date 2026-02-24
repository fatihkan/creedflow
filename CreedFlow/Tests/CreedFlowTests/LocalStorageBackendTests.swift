import Foundation
@testable import CreedFlowLib

enum LocalStorageBackendTests {
    static func runAll() {
        testWriteCreatesFileAndReturnsPath()
        testReadReturnsWrittenData()
        testExistsReturnsTrueForExistingFile()
        testExistsReturnsFalseForMissingFile()
        testDeleteRemovesFile()
        testWriteCreatesDirectoryStructure()
        testReadThrowsForMissingFile()
        print("  LocalStorageBackendTests: 7/7 passed")
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

    private static let testProjectName = "creedflow-test-\(UUID().uuidString)"

    private static func cleanupTestDir(backend: LocalAssetStorageBackend) {
        let dir = "\(backend.baseDirectory)/\(testProjectName)"
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - Tests

    static func testWriteCreatesFileAndReturnsPath() {
        let backend = LocalAssetStorageBackend()
        let projectName = "storage-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: "\(backend.baseDirectory)/\(projectName)") }

        let data = "Hello, CreedFlow!".data(using: .utf8)!
        let path = try! runBlocking { try await backend.write(data: data, fileName: "test.txt", projectName: projectName) }

        assertTrue(FileManager.default.fileExists(atPath: path))
        assertTrue(path.contains(projectName))
        assertTrue(path.hasSuffix("test.txt"))
    }

    static func testReadReturnsWrittenData() {
        let backend = LocalAssetStorageBackend()
        let projectName = "storage-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: "\(backend.baseDirectory)/\(projectName)") }

        let original = "Test data content 123".data(using: .utf8)!
        let path = try! runBlocking { try await backend.write(data: original, fileName: "data.bin", projectName: projectName) }
        let read = try! runBlocking { try await backend.read(filePath: path) }

        assertEq(original, read)
    }

    static func testExistsReturnsTrueForExistingFile() {
        let backend = LocalAssetStorageBackend()
        let projectName = "storage-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: "\(backend.baseDirectory)/\(projectName)") }

        let data = "exists".data(using: .utf8)!
        let path = try! runBlocking { try await backend.write(data: data, fileName: "check.txt", projectName: projectName) }

        assertTrue(backend.exists(filePath: path))
    }

    static func testExistsReturnsFalseForMissingFile() {
        let backend = LocalAssetStorageBackend()
        assertTrue(!backend.exists(filePath: "/nonexistent/path/file.txt"))
    }

    static func testDeleteRemovesFile() {
        let backend = LocalAssetStorageBackend()
        let projectName = "storage-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: "\(backend.baseDirectory)/\(projectName)") }

        let data = "to delete".data(using: .utf8)!
        let path = try! runBlocking { try await backend.write(data: data, fileName: "remove.txt", projectName: projectName) }
        assertTrue(backend.exists(filePath: path))

        try! runBlocking { try await backend.delete(filePath: path) }
        assertTrue(!backend.exists(filePath: path))
    }

    static func testWriteCreatesDirectoryStructure() {
        let backend = LocalAssetStorageBackend()
        let projectName = "storage-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: "\(backend.baseDirectory)/\(projectName)") }

        let expectedDir = "\(backend.baseDirectory)/\(projectName)/assets"
        assertTrue(!FileManager.default.fileExists(atPath: expectedDir), "dir should not exist before write")

        let data = "test".data(using: .utf8)!
        _ = try! runBlocking { try await backend.write(data: data, fileName: "file.txt", projectName: projectName) }

        var isDir: ObjCBool = false
        assertTrue(FileManager.default.fileExists(atPath: expectedDir, isDirectory: &isDir))
        assertTrue(isDir.boolValue)
    }

    static func testReadThrowsForMissingFile() {
        let backend = LocalAssetStorageBackend()
        do {
            _ = try runBlocking { try await backend.read(filePath: "/nonexistent/file.txt") }
            fatalError("Expected error for missing file")
        } catch {
            // Expected
        }
    }
}
