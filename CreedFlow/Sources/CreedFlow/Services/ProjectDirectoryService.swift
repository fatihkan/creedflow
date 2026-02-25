import Foundation

/// Manages project working directories under ~/CreedFlow/projects/
actor ProjectDirectoryService {
    private let baseDirectory: String

    init(baseDirectory: String? = nil) {
        if let base = baseDirectory {
            self.baseDirectory = base
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.baseDirectory = "\(home)/CreedFlow/projects"
        }
    }

    /// Create a new project directory and initialize git with three-branch structure (main → staging → dev).
    func createProjectDirectory(name: String) async throws -> String {
        let sanitized = sanitizeDirectoryName(name)
        let path = "\(baseDirectory)/\(sanitized)"
        let fm = FileManager.default

        // Create directory
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)

        // Initialize git repo
        let git = GitService()
        try await git.initRepo(at: path)

        // Create initial CLAUDE.md
        let claudeMD = """
            # \(name)

            This project is managed by CreedFlow.

            ## Conventions
            - Follow standard coding conventions for the project's tech stack
            - Write clean, readable code with meaningful names
            - Handle errors appropriately
            - Add comments only where logic is non-obvious
            """
        try claudeMD.write(toFile: "\(path)/CLAUDE.md", atomically: true, encoding: .utf8)

        // Create .gitignore
        let gitignore = """
            .DS_Store
            .build/
            *.xcodeproj/
            .swiftpm/
            node_modules/
            __pycache__/
            *.pyc
            .env
            """
        try gitignore.write(toFile: "\(path)/.gitignore", atomically: true, encoding: .utf8)

        // Initial commit on main
        try await git.addAll(in: path)
        try await git.commit(message: "chore: initial project setup", in: path)

        // Create staging branch from main
        try await git.createBranch("staging", in: path)
        try await git.checkout("main", in: path)

        // Create dev branch from main and stay on it
        try await git.createBranch("dev", in: path)

        return path
    }

    /// Generate/update CLAUDE.md for a project with tech stack and conventions
    func updateClaudeMD(at path: String, project: Project, conventions: String = "") throws {
        let content = """
            # \(project.name)

            \(project.description)

            ## Tech Stack
            \(project.techStack)

            ## Conventions
            \(conventions.isEmpty ? "- Follow standard conventions for the tech stack" : conventions)

            ## Status
            Managed by CreedFlow. Do not modify this file manually.
            """
        try content.write(toFile: "\(path)/CLAUDE.md", atomically: true, encoding: .utf8)
    }

    /// Check if a project directory exists
    func exists(name: String) -> Bool {
        let sanitized = sanitizeDirectoryName(name)
        let path = "\(baseDirectory)/\(sanitized)"
        return FileManager.default.fileExists(atPath: path)
    }

    /// Get the path for a project
    func path(for name: String) -> String {
        let sanitized = sanitizeDirectoryName(name)
        return "\(baseDirectory)/\(sanitized)"
    }

    /// List all project directories
    func listProjects() throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseDirectory) else { return [] }
        return try fm.contentsOfDirectory(atPath: baseDirectory)
            .filter { name in
                var isDir: ObjCBool = false
                fm.fileExists(atPath: "\(baseDirectory)/\(name)", isDirectory: &isDir)
                return isDir.boolValue
            }
    }

    /// Delete a project directory
    func deleteProjectDirectory(name: String) throws {
        let sanitized = sanitizeDirectoryName(name)
        let path = "\(baseDirectory)/\(sanitized)"
        try FileManager.default.removeItem(atPath: path)
    }

    private func sanitizeDirectoryName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
