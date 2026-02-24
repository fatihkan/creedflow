import Foundation

/// Abstraction for where asset files are stored (local filesystem, S3, etc.).
protocol AssetStorageBackend: Sendable {
    /// Write data to storage and return the absolute file path.
    func write(data: Data, fileName: String, projectName: String) async throws -> String

    /// Read data from a stored file.
    func read(filePath: String) async throws -> Data

    /// Delete a stored file.
    func delete(filePath: String) async throws

    /// Check if a file exists at the given path.
    func exists(filePath: String) -> Bool

    /// Base directory for this storage backend.
    var baseDirectory: String { get }
}
