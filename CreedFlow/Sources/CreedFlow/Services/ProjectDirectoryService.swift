import Foundation

/// Manages project working directories under ~/CreedFlow/projects/
actor ProjectDirectoryService {

    struct ImportValidation {
        let hasGitRepo: Bool
        let hasClaudeMD: Bool
        let detectedTechStack: String?
    }

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
    /// If the directory already exists with a git repo, reuses it and ensures branches exist.
    func createProjectDirectory(name: String) async throws -> String {
        let sanitized = sanitizeDirectoryName(name)
        let path = "\(baseDirectory)/\(sanitized)"
        let fm = FileManager.default

        // Create directory
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)

        let git = GitService()
        let gitDirExists = fm.fileExists(atPath: "\(path)/.git")

        if !gitDirExists {
            // Initialize git repo
            try await git.initRepo(at: path)
        }

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

        // Initial commit on main (may already exist if dir was reused)
        try await git.addAll(in: path)
        do {
            try await git.commit(message: "chore: initial project setup", in: path)
        } catch {
            // Commit may fail if nothing to commit (directory reuse) — that's OK
        }

        // Create branches if they don't exist yet (best-effort)
        let existingBranches = (try? await git.allBranches(in: path)) ?? []
        if !existingBranches.contains("staging") {
            try? await git.createBranch("staging", in: path)
            try? await git.checkout("main", in: path)
        }
        if !existingBranches.contains("dev") {
            try? await git.createBranch("dev", in: path)
        } else {
            // Ensure we're on dev
            try? await git.checkout("dev", in: path)
        }

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

    /// Generate/update CLAUDE.md from rich analyzer output.
    /// Keeps content concise (under 200 lines) so Claude Code can load it efficiently.
    func updateClaudeMDFromAnalysis(
        at path: String,
        project: Project,
        techStack: String?,
        architecture: String?,
        dataModels: [AnalysisDataModel]?,
        keyFiles: [String]
    ) throws {
        var lines: [String] = []

        // Header
        lines.append("# \(project.name)")
        lines.append("")
        if !project.description.isEmpty {
            lines.append(project.description)
            lines.append("")
        }

        // Tech Stack
        let stack = techStack ?? project.techStack
        if !stack.isEmpty {
            lines.append("## Tech Stack")
            lines.append(stack)
            lines.append("")
        }

        // Architecture summary (first 3 paragraphs or 500 chars)
        if let arch = architecture, !arch.isEmpty {
            lines.append("## Architecture")
            let trimmed = Self.trimArchitecture(arch)
            lines.append(trimmed)
            lines.append("")
            lines.append("Full architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)")
            lines.append("")
        }

        // Data Models (compact format)
        if let models = dataModels, !models.isEmpty {
            lines.append("## Data Models")
            for model in models {
                var entry = "- **\(model.name)**"
                if let type = model.type { entry += " (\(type))" }
                if let fields = model.fields, !fields.isEmpty {
                    let fieldNames = fields.prefix(8).map { $0.name }
                    entry += " — \(fieldNames.joined(separator: ", "))"
                    if fields.count > 8 { entry += ", ..." }
                }
                lines.append(entry)
            }
            lines.append("")
        }

        // Key Files
        if !keyFiles.isEmpty {
            lines.append("## Key Files")
            for file in keyFiles.prefix(30) {
                lines.append("- \(file)")
            }
            if keyFiles.count > 30 {
                lines.append("- ... and \(keyFiles.count - 30) more")
            }
            lines.append("")
        }

        // Conventions
        lines.append("## Conventions")
        lines.append("- Follow standard conventions for the tech stack")
        lines.append("- Handle errors appropriately")
        lines.append("- Add comments only where logic is non-obvious")
        lines.append("")

        // Diagrams reference
        lines.append("## Diagrams")
        lines.append("See [docs/diagrams/](docs/diagrams/) for Mermaid diagrams.")
        lines.append("")

        // Status
        lines.append("## Status")
        lines.append("Managed by CreedFlow. Analysis-generated — will be updated on re-analysis.")

        let content = lines.joined(separator: "\n")
        try content.write(toFile: "\(path)/CLAUDE.md", atomically: true, encoding: .utf8)
    }

    /// Trim architecture text to first 3 paragraphs or ~500 characters, whichever is shorter.
    private static func trimArchitecture(_ text: String) -> String {
        let paragraphs = text.components(separatedBy: "\n\n")
        let first3 = paragraphs.prefix(3).joined(separator: "\n\n")
        if first3.count <= 500 {
            return first3
        }
        // Trim to ~500 chars at a sentence boundary
        let trimmed = String(first3.prefix(500))
        if let lastDot = trimmed.lastIndex(of: ".") {
            return String(trimmed[...lastDot])
        }
        return trimmed + "..."
    }

    /// Validate an existing directory for import into CreedFlow.
    func validateImportPath(_ path: String) throws -> ImportValidation {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Directory does not exist: \(path)"])
        }

        let hasGitRepo = fm.fileExists(atPath: "\(path)/.git")
        let hasClaudeMD = fm.fileExists(atPath: "\(path)/CLAUDE.md")

        // Simple tech stack detection by manifest files
        let detectedTechStack: String? = {
            let markers: [(file: String, stack: String)] = [
                ("Package.swift", "Swift"),
                ("package.json", "Node.js"),
                ("Cargo.toml", "Rust"),
                ("go.mod", "Go"),
                ("pom.xml", "Java"),
                ("requirements.txt", "Python"),
                ("Gemfile", "Ruby"),
                ("composer.json", "PHP"),
                ("build.gradle", "Kotlin/Java"),
                ("CMakeLists.txt", "C/C++"),
                ("pubspec.yaml", "Dart/Flutter"),
            ]
            let detected = markers.filter { fm.fileExists(atPath: "\(path)/\($0.file)") }.map(\.stack)
            return detected.isEmpty ? nil : detected.joined(separator: ", ")
        }()

        return ImportValidation(hasGitRepo: hasGitRepo, hasClaudeMD: hasClaudeMD, detectedTechStack: detectedTechStack)
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
