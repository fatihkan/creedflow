import Foundation
import GRDB

/// Manifest describing a `.creedflow` bundle.
struct BundleManifest: Codable {
    var bundleVersion: Int
    var appVersion: String
    var exportedAt: Date
    var projectName: String
}

/// Exports and imports projects as portable `.creedflow` bundles (ZIP archives).
package actor ProjectBundleService {

    enum BundleError: LocalizedError {
        case zipFailed(Int32)
        case unzipFailed(Int32)
        case invalidBundle(String)

        var errorDescription: String? {
            switch self {
            case .zipFailed(let code):
                return "ZIP creation failed with exit code \(code)"
            case .unzipFailed(let code):
                return "Unzip failed with exit code \(code)"
            case .invalidBundle(let reason):
                return "Invalid bundle: \(reason)"
            }
        }
    }

    // MARK: - Export

    package func exportBundle(project: Project, dbQueue: DatabaseQueue, to outputURL: URL) throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("creedflow-bundle-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let bundleDir = tempDir.appendingPathComponent(project.name)
        try fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Query all related data
        let (features, tasks, dependencies, reviews) = try dbQueue.read { db -> ([Feature], [AgentTask], [TaskDependency], [Review]) in
            let features = try Feature
                .filter(Column("projectId") == project.id)
                .order(Column("priority").desc, Column("name").asc)
                .fetchAll(db)
            let tasks = try AgentTask
                .filter(Column("projectId") == project.id)
                .order(Column("priority").desc, Column("createdAt").asc)
                .fetchAll(db)
            let taskIds = tasks.map(\.id)
            let dependencies = try TaskDependency
                .filter(taskIds.contains(Column("taskId")))
                .fetchAll(db)
            let reviews = try Review
                .filter(taskIds.contains(Column("taskId")))
                .order(Column("createdAt").desc)
                .fetchAll(db)
            return (features, tasks, dependencies, reviews)
        }

        // Write manifest.json
        let manifest = BundleManifest(
            bundleVersion: 1,
            appVersion: "1.0.0",
            exportedAt: Date(),
            projectName: project.name
        )
        try encoder.encode(manifest).write(to: bundleDir.appendingPathComponent("manifest.json"))

        // Write project.json
        try encoder.encode(project).write(to: bundleDir.appendingPathComponent("project.json"))

        // Write features.json
        try encoder.encode(features).write(to: bundleDir.appendingPathComponent("features.json"))

        // Write tasks.json
        try encoder.encode(tasks).write(to: bundleDir.appendingPathComponent("tasks.json"))

        // Write dependencies.json
        try encoder.encode(dependencies).write(to: bundleDir.appendingPathComponent("dependencies.json"))

        // Write reviews.json
        try encoder.encode(reviews).write(to: bundleDir.appendingPathComponent("reviews.json"))

        // Copy project directory files into files/ subdirectory
        let filesDir = bundleDir.appendingPathComponent("files")
        try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
        let projectDir = URL(fileURLWithPath: project.directoryPath)
        if fm.fileExists(atPath: project.directoryPath) {
            let contents = try fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for item in contents {
                let dest = filesDir.appendingPathComponent(item.lastPathComponent)
                try fm.copyItem(at: item, to: dest)
            }
        }

        // ZIP with /usr/bin/zip → rename to .creedflow
        let zipPath = tempDir.appendingPathComponent("\(project.name).zip").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", zipPath, project.name]
        process.currentDirectoryURL = tempDir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BundleError.zipFailed(process.terminationStatus)
        }

        // Move to output URL (with .creedflow extension)
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }
        try fm.moveItem(atPath: zipPath, toPath: outputURL.path)
    }

    // MARK: - Import

    package func importBundle(from inputURL: URL, dbQueue: DatabaseQueue) throws -> Project {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("creedflow-import-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", inputURL.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BundleError.unzipFailed(process.terminationStatus)
        }

        // Find the bundle root directory (first directory inside tempDir)
        let topItems = try fm.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        guard let bundleDir = topItems.first(where: {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }) else {
            throw BundleError.invalidBundle("No directory found in bundle")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Read manifest.json
        let manifestURL = bundleDir.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw BundleError.invalidBundle("Missing manifest.json")
        }
        let manifest = try decoder.decode(BundleManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.bundleVersion == 1 else {
            throw BundleError.invalidBundle("Unsupported bundle version: \(manifest.bundleVersion)")
        }

        // Read project.json
        let projectURL = bundleDir.appendingPathComponent("project.json")
        guard fm.fileExists(atPath: projectURL.path) else {
            throw BundleError.invalidBundle("Missing project.json")
        }
        let originalProject = try decoder.decode(Project.self, from: Data(contentsOf: projectURL))

        // Read features.json
        let featuresURL = bundleDir.appendingPathComponent("features.json")
        let originalFeatures: [Feature] = fm.fileExists(atPath: featuresURL.path)
            ? try decoder.decode([Feature].self, from: Data(contentsOf: featuresURL))
            : []

        // Read tasks.json
        let tasksURL = bundleDir.appendingPathComponent("tasks.json")
        let originalTasks: [AgentTask] = fm.fileExists(atPath: tasksURL.path)
            ? try decoder.decode([AgentTask].self, from: Data(contentsOf: tasksURL))
            : []

        // Read dependencies.json
        let depsURL = bundleDir.appendingPathComponent("dependencies.json")
        let originalDeps: [TaskDependency] = fm.fileExists(atPath: depsURL.path)
            ? try decoder.decode([TaskDependency].self, from: Data(contentsOf: depsURL))
            : []

        // Read reviews.json
        let reviewsURL = bundleDir.appendingPathComponent("reviews.json")
        let originalReviews: [Review] = fm.fileExists(atPath: reviewsURL.path)
            ? try decoder.decode([Review].self, from: Data(contentsOf: reviewsURL))
            : []

        // Build UUID mapping: old → new
        let newProjectId = UUID()
        var idMap: [UUID: UUID] = [originalProject.id: newProjectId]

        for feature in originalFeatures {
            idMap[feature.id] = UUID()
        }
        for task in originalTasks {
            idMap[task.id] = UUID()
        }
        for review in originalReviews {
            idMap[review.id] = UUID()
        }

        // Create project directory
        let projectsBase = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("CreedFlow/projects/\(originalProject.name)")
        try fm.createDirectory(at: projectsBase, withIntermediateDirectories: true)

        // Copy files/ contents into new project directory
        let filesDir = bundleDir.appendingPathComponent("files")
        if fm.fileExists(atPath: filesDir.path) {
            let fileContents = try fm.contentsOfDirectory(
                at: filesDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for item in fileContents {
                let dest = projectsBase.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: item, to: dest)
            }
        }

        // Build new records with remapped UUIDs
        let now = Date()
        let newProject = Project(
            id: newProjectId,
            name: originalProject.name,
            description: originalProject.description,
            techStack: originalProject.techStack,
            status: originalProject.status,
            directoryPath: projectsBase.path,
            projectType: originalProject.projectType,
            stagingPrNumber: nil,
            completedAt: originalProject.completedAt,
            telegramChatId: nil,
            createdAt: now,
            updatedAt: now
        )

        let newFeatures: [Feature] = originalFeatures.map { f in
            Feature(
                id: idMap[f.id]!,
                projectId: newProjectId,
                name: f.name,
                description: f.description,
                priority: f.priority,
                status: f.status,
                integrationPrNumber: nil,
                createdAt: f.createdAt,
                updatedAt: f.updatedAt
            )
        }

        let newTasks: [AgentTask] = originalTasks.map { t in
            AgentTask(
                id: idMap[t.id]!,
                projectId: newProjectId,
                featureId: t.featureId.flatMap { idMap[$0] },
                agentType: t.agentType,
                title: t.title,
                description: t.description,
                priority: t.priority,
                status: t.status,
                result: t.result,
                errorMessage: t.errorMessage,
                retryCount: t.retryCount,
                maxRetries: t.maxRetries,
                createdAt: t.createdAt,
                updatedAt: t.updatedAt,
                completedAt: t.completedAt,
                backend: t.backend
            )
        }

        let newDeps: [TaskDependency] = originalDeps.compactMap { d in
            guard let newTaskId = idMap[d.taskId],
                  let newDepId = idMap[d.dependsOnTaskId] else { return nil }
            return TaskDependency(taskId: newTaskId, dependsOnTaskId: newDepId)
        }

        let newReviews: [Review] = originalReviews.map { r in
            Review(
                id: idMap[r.id]!,
                taskId: idMap[r.taskId]!,
                score: r.score,
                verdict: r.verdict,
                summary: r.summary,
                issues: r.issues,
                suggestions: r.suggestions,
                securityNotes: r.securityNotes,
                costUSD: r.costUSD,
                isApproved: r.isApproved,
                createdAt: r.createdAt
            )
        }

        // Insert all records in a single transaction
        try dbQueue.write { db in
            try newProject.insert(db)
            for feature in newFeatures {
                try feature.insert(db)
            }
            for task in newTasks {
                try task.insert(db)
            }
            for dep in newDeps {
                try dep.insert(db)
            }
            for review in newReviews {
                try review.insert(db)
            }
        }

        return newProject
    }
}
