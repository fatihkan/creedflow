import AppKit
import Foundation

/// A system dependency that can be detected and installed via Homebrew.
struct SystemDependency: Identifiable {
    let id: String
    let name: String
    let description: String
    let candidates: [String]
    let installCommand: String
    let isBrewCask: Bool
    /// macOS bundle identifier for .app detection via NSWorkspace (optional)
    let bundleId: String?
    /// Custom install script (overrides brew install when set)
    let customInstall: String?
    var isInstalled: Bool = false
    var detectedVersion: String = ""
    var isInstalling: Bool = false
    var installOutput: String = ""
    var installError: String?

    init(
        id: String, name: String, description: String,
        candidates: [String], installCommand: String, isBrewCask: Bool,
        bundleId: String? = nil, customInstall: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.candidates = candidates
        self.installCommand = installCommand
        self.isBrewCask = isBrewCask
        self.bundleId = bundleId
        self.customInstall = customInstall
    }
}

/// Detects and installs system dependencies (Docker, git, gh, node, editors, etc.)
/// via Homebrew for the setup wizard.
@Observable
final class DependencyInstaller {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    private(set) var isDetecting = false
    private(set) var isInstallingAll = false

    private(set) var brewDetected = false
    private(set) var brewPath = ""
    private(set) var brewVersion = ""
    private(set) var isInstallingBrew = false
    private(set) var brewInstallOutput = ""
    private(set) var brewInstallError: String?

    private(set) var dependencies: [SystemDependency] = []

    var missingCount: Int {
        dependencies.filter { !$0.isInstalled }.count
    }

    var anyInstalling: Bool {
        isInstallingBrew || dependencies.contains(where: { $0.isInstalling })
    }

    private static let brewCandidates = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    init() {
        dependencies = Self.defaultDependencies()
    }

    private static func defaultDependencies() -> [SystemDependency] {
        [
            // --- Dev Tools ---
            SystemDependency(
                id: "xcode-cli",
                name: "Xcode CLI Tools",
                description: "Git, compilers, and developer tools",
                candidates: ["/usr/bin/xcodebuild", "/usr/bin/git"],
                installCommand: "",
                isBrewCask: false,
                customInstall: "xcode-select --install"
            ),
            SystemDependency(
                id: "docker",
                name: "Docker",
                description: "Container runtime for deployments",
                candidates: ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"],
                installCommand: "docker",
                isBrewCask: true,
                bundleId: "com.docker.docker"
            ),
            SystemDependency(
                id: "git",
                name: "Git",
                description: "Version control (usually pre-installed)",
                candidates: ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"],
                installCommand: "git",
                isBrewCask: false
            ),
            SystemDependency(
                id: "gh",
                name: "GitHub CLI",
                description: "Create PRs and manage GitHub repos",
                candidates: ["/usr/local/bin/gh", "/opt/homebrew/bin/gh"],
                installCommand: "gh",
                isBrewCask: false
            ),
            SystemDependency(
                id: "node",
                name: "Node.js",
                description: "Required for Codex CLI and Gemini CLI",
                candidates: [
                    "/usr/local/bin/node",
                    "/opt/homebrew/bin/node",
                    "\(home)/.nvm/versions/node/*/bin/node",
                ],
                installCommand: "node",
                isBrewCask: false
            ),
            SystemDependency(
                id: "go",
                name: "Go",
                description: "Required for OpenCode CLI",
                candidates: ["/usr/local/bin/go", "/opt/homebrew/bin/go", "\(home)/go/bin/go"],
                installCommand: "go",
                isBrewCask: false
            ),
            SystemDependency(
                id: "python3",
                name: "Python 3",
                description: "Required for MLX-LM local backend",
                candidates: [
                    "/usr/bin/python3",
                    "/usr/local/bin/python3",
                    "/opt/homebrew/bin/python3",
                ],
                installCommand: "python",
                isBrewCask: false
            ),
            SystemDependency(
                id: "ollama",
                name: "Ollama",
                description: "Local LLM backend",
                candidates: ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"],
                installCommand: "ollama",
                isBrewCask: false
            ),
            SystemDependency(
                id: "llama-cli",
                name: "llama.cpp",
                description: "Local LLM backend (GGUF models)",
                candidates: ["/opt/homebrew/bin/llama-cli", "/usr/local/bin/llama-cli"],
                installCommand: "llama.cpp",
                isBrewCask: false
            ),

            // --- Code Editors ---
            SystemDependency(
                id: "vscode",
                name: "VS Code",
                description: "Popular code editor by Microsoft",
                candidates: [
                    "/usr/local/bin/code",
                    "\(home)/.local/bin/code",
                    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
                ],
                installCommand: "visual-studio-code",
                isBrewCask: true,
                bundleId: "com.microsoft.VSCode"
            ),
            SystemDependency(
                id: "cursor",
                name: "Cursor",
                description: "AI-powered code editor",
                candidates: [
                    "/usr/local/bin/cursor",
                    "\(home)/.local/bin/cursor",
                    "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
                ],
                installCommand: "cursor",
                isBrewCask: true,
                bundleId: "com.todesktop.230313mzl4w4u92"
            ),
            SystemDependency(
                id: "zed",
                name: "Zed",
                description: "High-performance code editor",
                candidates: [
                    "/usr/local/bin/zed",
                    "\(home)/.local/bin/zed",
                    "/Applications/Zed.app/Contents/MacOS/cli/zed",
                ],
                installCommand: "zed",
                isBrewCask: true,
                bundleId: "dev.zed.Zed"
            ),
            SystemDependency(
                id: "windsurf",
                name: "Windsurf",
                description: "AI-powered code editor by Codeium",
                candidates: [
                    "/usr/local/bin/windsurf",
                    "\(home)/.local/bin/windsurf",
                    "/Applications/Windsurf.app/Contents/Resources/app/bin/windsurf",
                ],
                installCommand: "windsurf",
                isBrewCask: true,
                bundleId: "com.codeium.windsurf"
            ),
        ]
    }

    // MARK: - Detection

    /// Detect Homebrew and all dependencies in parallel.
    func detectAll() async {
        isDetecting = true
        defer { isDetecting = false }

        // Detect Homebrew first
        await detectBrew()

        // Detect all deps in parallel
        await withTaskGroup(of: (Int, Bool, String).self) { group in
            for (index, dep) in dependencies.enumerated() {
                group.addTask { [dep] in
                    let (found, version) = await self.detectDependency(dep)
                    return (index, found, version)
                }
            }
            for await (index, found, version) in group {
                dependencies[index].isInstalled = found
                dependencies[index].detectedVersion = version
            }
        }
    }

    private func detectBrew() async {
        for candidate in Self.brewCandidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                brewPath = candidate
                do {
                    let output = try await Process.run(candidate, arguments: ["--version"])
                    brewVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: "\n").first ?? ""
                    brewDetected = true
                } catch {
                    brewVersion = ""
                    brewDetected = true
                }
                return
            }
        }
        brewDetected = false
        brewPath = ""
        brewVersion = ""
    }

    private func detectDependency(_ dep: SystemDependency) async -> (Bool, String) {
        // Special case: Xcode CLI Tools
        if dep.id == "xcode-cli" {
            return await detectXcodeCliTools()
        }

        // Primary: use NSWorkspace to find installed .app by bundle ID
        if let bundleId = dep.bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            // Try to get version from the app's Info.plist
            let version = Self.appVersion(at: appURL) ?? ""
            return (true, version.isEmpty ? "Installed" : version)
        }

        // Fallback: check CLI candidate paths
        for candidate in dep.candidates {
            // Support glob-like patterns (e.g. nvm paths with *)
            if candidate.contains("*") {
                let matches = expandGlob(candidate)
                for match in matches {
                    if FileManager.default.isExecutableFile(atPath: match) {
                        let version = await getVersion(match)
                        return (true, version)
                    }
                }
            } else if FileManager.default.isExecutableFile(atPath: candidate) {
                let version = await getVersion(candidate)
                return (true, version)
            }
        }
        return (false, "")
    }

    private func detectXcodeCliTools() async -> (Bool, String) {
        do {
            let output = try await Process.run("/usr/bin/xcode-select", arguments: ["-p"])
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                // Get CLT version
                let versionOutput = try? await Process.run("/usr/bin/xcodebuild", arguments: ["-version"])
                let version = versionOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "\n").first ?? "Installed"
                return (true, version)
            }
        } catch {}
        return (false, "")
    }

    /// Read CFBundleShortVersionString from an app's Info.plist
    private static func appVersion(at appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return version
    }

    private func getVersion(_ path: String) async -> String {
        do {
            let output = try await Process.run(path, arguments: ["--version"])
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? ""
        } catch {
            return ""
        }
    }

    private func expandGlob(_ pattern: String) -> [String] {
        // Simple glob expansion for paths like ~/.nvm/versions/node/*/bin/node
        let components = pattern.components(separatedBy: "/")
        guard let starIndex = components.firstIndex(where: { $0 == "*" }) else {
            return [pattern]
        }
        let basePath = components[0..<starIndex].joined(separator: "/")
        let suffix = components[(starIndex + 1)...].joined(separator: "/")

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: basePath) else {
            return []
        }
        return contents
            .sorted().reversed() // newest version first
            .map { "\(basePath)/\($0)/\(suffix)" }
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Installation

    /// Install Homebrew via the official install script.
    func installBrew() async {
        isInstallingBrew = true
        brewInstallOutput = ""
        brewInstallError = nil
        defer { isInstallingBrew = false }

        let script = "/bin/bash"
        let args = ["-c", "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""]

        do {
            let (output, error) = await runProcessStreaming(script, arguments: args)
            brewInstallOutput = output
            if !error.isEmpty && !output.contains("Installation successful") {
                brewInstallError = error
            }
        }

        // Re-detect after install
        await detectBrew()
    }

    /// Install a single dependency via Homebrew (or custom install command).
    func install(_ depId: String) async {
        guard let index = dependencies.firstIndex(where: { $0.id == depId }) else { return }

        dependencies[index].isInstalling = true
        dependencies[index].installOutput = ""
        dependencies[index].installError = nil
        defer { dependencies[index].isInstalling = false }

        let dep = dependencies[index]

        // Special: custom install command (e.g. xcode-select --install)
        if let customInstall = dep.customInstall {
            let components = customInstall.components(separatedBy: " ")
            guard let executable = components.first else { return }
            let args = Array(components.dropFirst())

            let (output, error) = await runProcessStreaming(executable, arguments: args)
            dependencies[index].installOutput = output
            if !error.isEmpty {
                dependencies[index].installError = error
            }

            // Re-detect
            let (found, version) = await detectDependency(dependencies[index])
            dependencies[index].isInstalled = found
            dependencies[index].detectedVersion = version
            return
        }

        guard brewDetected else { return }

        var args = ["install"]
        if dep.isBrewCask { args.append("--cask") }
        args.append(dep.installCommand)

        let (output, error) = await runProcessStreaming(brewPath, arguments: args)
        dependencies[index].installOutput = output
        // Homebrew cask writes success messages to stderr, so check combined output
        let combined = output + " " + error
        let isSuccess = combined.contains("successfully installed")
            || combined.contains("was successfully installed")
            || combined.contains("Pouring")
            || combined.contains("Moving App")
            || combined.contains("is already installed")
        if !error.isEmpty && !isSuccess {
            dependencies[index].installError = error
        }

        // Re-detect this dep
        let (found, version) = await detectDependency(dependencies[index])
        dependencies[index].isInstalled = found
        dependencies[index].detectedVersion = version
    }

    /// Install all missing dependencies sequentially.
    func installAllMissing() async {
        isInstallingAll = true
        defer { isInstallingAll = false }

        for dep in dependencies where !dep.isInstalled {
            await install(dep.id)
        }
    }

    // MARK: - Process Helper

    /// Run a process and return (stdout, stderr) after completion.
    private func runProcessStreaming(_ executablePath: String, arguments: [String]) async -> (String, String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            // Inherit environment for PATH, API keys, etc.
            var env = ProcessInfo.processInfo.environment
            // Ensure Homebrew is on PATH
            if !brewPath.isEmpty {
                let brewBin = (brewPath as NSString).deletingLastPathComponent
                let currentPath = env["PATH"] ?? "/usr/bin:/bin"
                if !currentPath.contains(brewBin) {
                    env["PATH"] = "\(brewBin):\(currentPath)"
                }
            }
            // Skip slow auto-update during installs
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { _ in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: (out, err))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ("", error.localizedDescription))
            }
        }
    }
}
