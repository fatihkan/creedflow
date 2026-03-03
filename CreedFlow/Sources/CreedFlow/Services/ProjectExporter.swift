import Foundation
import GRDB

package struct ProjectExporter {
    /// Export a project as a ZIP archive containing project files, tasks JSON, and reviews JSON.
    package static func exportAsZIP(
        project: Project,
        dbQueue: DatabaseQueue,
        to outputURL: URL
    ) throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("creedflow-export-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let exportDir = tempDir.appendingPathComponent(project.name)
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Copy project directory contents if it exists
        let projectDir = URL(fileURLWithPath: project.directoryPath)
        if fm.fileExists(atPath: project.directoryPath) {
            let contents = try fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for item in contents {
                let dest = exportDir.appendingPathComponent(item.lastPathComponent)
                try fm.copyItem(at: item, to: dest)
            }
        }

        // Fetch tasks and reviews from DB
        let (tasks, reviews) = try dbQueue.read { db -> ([AgentTask], [Review]) in
            let tasks = try AgentTask
                .filter(Column("projectId") == project.id)
                .order(Column("priority").desc, Column("createdAt").asc)
                .fetchAll(db)
            let taskIds = tasks.map(\.id)
            let reviews = try Review
                .filter(taskIds.contains(Column("taskId")))
                .order(Column("createdAt").desc)
                .fetchAll(db)
            return (tasks, reviews)
        }

        // Write tasks.json
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let tasksData = try encoder.encode(tasks)
        try tasksData.write(to: exportDir.appendingPathComponent("tasks.json"))

        // Write reviews.json
        let reviewsData = try encoder.encode(reviews)
        try reviewsData.write(to: exportDir.appendingPathComponent("reviews.json"))

        // Run zip command (macOS ships with /usr/bin/zip)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", outputURL.path, project.name]
        process.currentDirectoryURL = tempDir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExportError.zipFailed(process.terminationStatus)
        }
    }

    enum ExportError: LocalizedError {
        case zipFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .zipFailed(let code):
                return "ZIP creation failed with exit code \(code)"
            }
        }
    }
}
