import Foundation

/// Local filesystem storage backend for assets.
/// Stores files under ~/CreedFlow/projects/{projectName}/assets/
struct LocalAssetStorageBackend: AssetStorageBackend {
    let baseDirectory: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.baseDirectory = "\(home)/CreedFlow/projects"
    }

    func write(data: Data, fileName: String, projectName: String) async throws -> String {
        let dir = assetsDir(projectName: projectName)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let filePath = (dir as NSString).appendingPathComponent(fileName)
        try data.write(to: URL(fileURLWithPath: filePath))
        return filePath
    }

    func read(filePath: String) async throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: filePath))
    }

    func delete(filePath: String) async throws {
        try FileManager.default.removeItem(atPath: filePath)
    }

    func exists(filePath: String) -> Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    private func assetsDir(projectName: String) -> String {
        "\(baseDirectory)/\(projectName)/assets"
    }
}
