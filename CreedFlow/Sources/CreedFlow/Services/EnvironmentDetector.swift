import AppKit
import Foundation

/// Auto-detects installed developer tools (AI CLIs, gh CLI, git config)
/// for the setup wizard and settings display.
@Observable
final class EnvironmentDetector {
    // AI CLIs
    var claudePath: String = ""
    var claudeVersion: String = ""
    var codexPath: String = ""
    var codexVersion: String = ""
    var geminiPath: String = ""
    var geminiVersion: String = ""

    // OpenCode
    var opencodePath: String = ""
    var opencodeVersion: String = ""

    // Local LLMs
    var ollamaPath: String = ""
    var ollamaVersion: String = ""
    var lmstudioPath: String = ""
    var lmstudioVersion: String = ""
    var llamacppPath: String = ""
    var llamacppVersion: String = ""
    var mlxPath: String = ""
    var mlxVersion: String = ""

    // Dev tools
    var ghPath: String = ""
    var ghVersion: String = ""
    var gitUserName: String = ""
    var gitUserEmail: String = ""

    // Code editors
    var detectedEditors: [(name: String, command: String, path: String)] = []

    var isDetecting = false

    // Install state per CLI
    var claudeInstalling = false
    var claudeInstallError: String?
    var codexInstalling = false
    var codexInstallError: String?
    var geminiInstalling = false
    var geminiInstallError: String?
    var opencodeInstalling = false
    var opencodeInstallError: String?
    var ollamaInstalling = false
    var ollamaInstallError: String?
    var lmstudioInstalling = false
    var lmstudioInstallError: String?
    var llamacppInstalling = false
    var llamacppInstallError: String?
    var mlxInstalling = false
    var mlxInstallError: String?

    var claudeFound: Bool { !claudePath.isEmpty && !claudeVersion.isEmpty }
    var codexFound: Bool { !codexPath.isEmpty && !codexVersion.isEmpty }
    var geminiFound: Bool { !geminiPath.isEmpty && !geminiVersion.isEmpty }
    var opencodeFound: Bool { !opencodePath.isEmpty && !opencodeVersion.isEmpty }
    var ollamaFound: Bool { !ollamaPath.isEmpty && !ollamaVersion.isEmpty }
    var lmstudioFound: Bool { !lmstudioPath.isEmpty && !lmstudioVersion.isEmpty }
    var llamacppFound: Bool { !llamacppPath.isEmpty && !llamacppVersion.isEmpty }
    var mlxFound: Bool { !mlxPath.isEmpty && !mlxVersion.isEmpty }
    var ghFound: Bool { !ghPath.isEmpty && !ghVersion.isEmpty }
    var gitConfigured: Bool { !gitUserName.isEmpty && !gitUserEmail.isEmpty }

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    private static let claudeCandidates = [
        "\(home)/.local/bin/claude",
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
    ]

    private static let codexCandidates = [
        "\(home)/.local/bin/codex",
        "/usr/local/bin/codex",
        "/opt/homebrew/bin/codex",
        "\(home)/.npm-global/bin/codex",
    ]

    private static let geminiCandidates = [
        "\(home)/.local/bin/gemini",
        "/usr/local/bin/gemini",
        "/opt/homebrew/bin/gemini",
        "\(home)/.npm-global/bin/gemini",
    ]

    private static let opencodeCandidates = [
        "\(home)/.local/bin/opencode",
        "/usr/local/bin/opencode",
        "/opt/homebrew/bin/opencode",
        "\(home)/go/bin/opencode",
    ]

    private static let ollamaCandidates = [
        "/usr/local/bin/ollama",
        "/opt/homebrew/bin/ollama",
    ]

    private static let lmstudioCandidates = [
        "\(home)/.local/bin/lms",
        "/usr/local/bin/lms",
        "/opt/homebrew/bin/lms",
    ]

    private static let llamacppCandidates = [
        "/opt/homebrew/bin/llama-cli",
        "/usr/local/bin/llama-cli",
    ]

    private static let mlxCandidates = [
        "\(home)/.local/bin/mlx_lm.generate",
        "/opt/homebrew/bin/mlx_lm.generate",
        "/usr/local/bin/mlx_lm.generate",
    ]

    private static let ghCandidates = [
        "/usr/local/bin/gh",
        "/opt/homebrew/bin/gh",
    ]

    /// Editor candidates: (display name, CLI command, bundle ID for NSWorkspace lookup, CLI paths)
    private static let editorCandidates: [(name: String, command: String, bundleId: String, paths: [String])] = [
        ("VS Code", "code", "com.microsoft.VSCode", [
            "/usr/local/bin/code",
            "\(home)/.local/bin/code",
            "/opt/homebrew/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
        ]),
        ("Cursor", "cursor", "com.todesktop.230313mzl4w4u92", [
            "/usr/local/bin/cursor",
            "\(home)/.local/bin/cursor",
            "/opt/homebrew/bin/cursor",
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
        ]),
        ("Zed", "zed", "dev.zed.Zed", [
            "/usr/local/bin/zed",
            "\(home)/.local/bin/zed",
            "/opt/homebrew/bin/zed",
            "/Applications/Zed.app/Contents/MacOS/cli/zed",
        ]),
        ("Sublime Text", "subl", "com.sublimetext.4", [
            "/usr/local/bin/subl",
            "/opt/homebrew/bin/subl",
            "/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl",
        ]),
        ("Xcode", "xed", "com.apple.dt.Xcode", ["/usr/bin/xed"]),
        ("Windsurf", "windsurf", "com.codeium.windsurf", [
            "/usr/local/bin/windsurf",
            "\(home)/.local/bin/windsurf",
            "/Applications/Windsurf.app/Contents/Resources/app/bin/windsurf",
        ]),
    ]

    /// Auto-detect all tools using candidate paths
    func detectAll() async {
        await detectAll(
            claudeOverride: "", codexOverride: "", geminiOverride: "",
            opencodeOverride: "",
            ollamaOverride: "", lmstudioOverride: "", llamacppOverride: "", mlxOverride: ""
        )
    }

    /// Detect all tools, preferring user-provided override paths when non-empty
    func detectAll(
        claudeOverride: String, codexOverride: String, geminiOverride: String,
        opencodeOverride: String = "",
        ollamaOverride: String = "", lmstudioOverride: String = "",
        llamacppOverride: String = "", mlxOverride: String = ""
    ) async {
        isDetecting = true
        defer { isDetecting = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.detectCLI(override: claudeOverride, candidates: Self.claudeCandidates) { path, version in
                self.claudePath = path; self.claudeVersion = version
            }}
            group.addTask { await self.detectCLI(override: codexOverride, candidates: Self.codexCandidates) { path, version in
                self.codexPath = path; self.codexVersion = version
            }}
            group.addTask { await self.detectCLI(override: geminiOverride, candidates: Self.geminiCandidates) { path, version in
                self.geminiPath = path; self.geminiVersion = version
            }}
            group.addTask { await self.detectCLI(override: opencodeOverride, candidates: Self.opencodeCandidates) { path, version in
                self.opencodePath = path; self.opencodeVersion = version
            }}
            group.addTask { await self.detectCLI(override: ollamaOverride, candidates: Self.ollamaCandidates) { path, version in
                self.ollamaPath = path; self.ollamaVersion = version
            }}
            group.addTask { await self.detectCLI(override: lmstudioOverride, candidates: Self.lmstudioCandidates) { path, version in
                self.lmstudioPath = path; self.lmstudioVersion = version
            }}
            group.addTask { await self.detectCLI(override: llamacppOverride, candidates: Self.llamacppCandidates) { path, version in
                self.llamacppPath = path; self.llamacppVersion = version
            }}
            group.addTask { await self.detectCLI(override: mlxOverride, candidates: Self.mlxCandidates, versionArgs: ["--help"]) { path, version in
                self.mlxPath = path; self.mlxVersion = version
            }}
            group.addTask { await self.detectCLI(override: "", candidates: Self.ghCandidates) { path, version in
                self.ghPath = path; self.ghVersion = version
            }}
            group.addTask { await self.detectGit() }
            group.addTask { await self.detectEditors() }
        }
    }

    // MARK: - Generic CLI Detection

    private func detectCLI(
        override: String,
        candidates: [String],
        versionArgs: [String] = ["--version"],
        apply: (String, String) -> Void
    ) async {
        var resolved = ""

        // Override path takes priority
        if !override.isEmpty {
            if FileManager.default.isExecutableFile(atPath: override) {
                resolved = override
            } else {
                // User gave a path but it's not executable
                apply(override, "")
                return
            }
        }

        // Fall back to candidate scan
        if resolved.isEmpty {
            for candidate in candidates {
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    resolved = candidate
                    break
                }
            }
        }

        guard !resolved.isEmpty else {
            apply("", "")
            return
        }

        do {
            let output = try await Process.run(resolved, arguments: versionArgs)
            let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? ""
            apply(resolved, version)
        } catch {
            apply(resolved, "")
        }
    }

    // MARK: - Code Editor Detection

    private func detectEditors() async {
        var found: [(name: String, command: String, path: String)] = []
        for editor in Self.editorCandidates {
            // Primary: use NSWorkspace to find installed .app by bundle ID (always works, even in .app bundles)
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleId) {
                // Derive CLI path from .app bundle location
                let cliPath = Self.cliPathFromApp(appURL: appURL, command: editor.command)
                found.append((name: editor.name, command: editor.command, path: cliPath ?? appURL.path))
                continue
            }
            // Fallback: check hardcoded CLI candidate paths
            for candidate in editor.paths {
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    found.append((name: editor.name, command: editor.command, path: candidate))
                    break
                }
            }
        }
        detectedEditors = found
    }

    /// Derive the CLI binary path from a .app bundle URL.
    private static func cliPathFromApp(appURL: URL, command: String) -> String? {
        let possibleRelPaths = [
            "Contents/Resources/app/bin/\(command)",  // VS Code, Cursor, Windsurf
            "Contents/MacOS/cli/\(command)",           // Zed
            "Contents/SharedSupport/bin/\(command)",   // Sublime Text
        ]
        for rel in possibleRelPaths {
            let fullPath = appURL.appendingPathComponent(rel).path
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    // MARK: - Git Config

    private func detectGit() async {
        do {
            let name = try await Process.run("/usr/bin/git", arguments: ["config", "--global", "user.name"])
            gitUserName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            gitUserName = ""
        }

        do {
            let email = try await Process.run("/usr/bin/git", arguments: ["config", "--global", "user.email"])
            gitUserEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            gitUserEmail = ""
        }
    }

    /// Set git global user.name and user.email, then re-detect.
    func configureGit(userName: String, email: String) async {
        if !userName.isEmpty {
            _ = try? await Process.run("/usr/bin/git", arguments: ["config", "--global", "user.name", userName])
        }
        if !email.isEmpty {
            _ = try? await Process.run("/usr/bin/git", arguments: ["config", "--global", "user.email", email])
        }
        await detectGit()
    }

    // MARK: - CLI Installation

    /// Install a CLI by its identifier (e.g. "claude", "codex", "gemini", etc.)
    func installCLI(_ cliId: String) async {
        switch cliId {
        case "claude":
            await installNpmCLI(id: "claude", package: "@anthropic-ai/claude-code",
                                installing: \.claudeInstalling, error: \.claudeInstallError,
                                candidates: Self.claudeCandidates) { p, v in self.claudePath = p; self.claudeVersion = v }
        case "codex":
            await installNpmCLI(id: "codex", package: "@openai/codex",
                                installing: \.codexInstalling, error: \.codexInstallError,
                                candidates: Self.codexCandidates) { p, v in self.codexPath = p; self.codexVersion = v }
        case "gemini":
            await installNpmCLI(id: "gemini", package: "@google/gemini-cli",
                                installing: \.geminiInstalling, error: \.geminiInstallError,
                                candidates: Self.geminiCandidates) { p, v in self.geminiPath = p; self.geminiVersion = v }
        case "opencode":
            await installGoCLI(
                installing: \.opencodeInstalling, error: \.opencodeInstallError,
                candidates: Self.opencodeCandidates) { p, v in self.opencodePath = p; self.opencodeVersion = v }
        case "ollama":
            await installBrewCLI(formula: "ollama", isCask: false,
                                 installing: \.ollamaInstalling, error: \.ollamaInstallError,
                                 candidates: Self.ollamaCandidates) { p, v in self.ollamaPath = p; self.ollamaVersion = v }
        case "lmstudio":
            await installBrewCLI(formula: "lm-studio", isCask: true,
                                 installing: \.lmstudioInstalling, error: \.lmstudioInstallError,
                                 candidates: Self.lmstudioCandidates) { p, v in self.lmstudioPath = p; self.lmstudioVersion = v }
        case "llamacpp":
            await installBrewCLI(formula: "llama.cpp", isCask: false,
                                 installing: \.llamacppInstalling, error: \.llamacppInstallError,
                                 candidates: Self.llamacppCandidates) { p, v in self.llamacppPath = p; self.llamacppVersion = v }
        case "mlx":
            await installPipCLI(
                installing: \.mlxInstalling, error: \.mlxInstallError,
                candidates: Self.mlxCandidates) { p, v in self.mlxPath = p; self.mlxVersion = v }
        default:
            break
        }
    }

    // MARK: - Install Helpers

    private func installNpmCLI(
        id: String, package: String,
        installing: ReferenceWritableKeyPath<EnvironmentDetector, Bool>,
        error: ReferenceWritableKeyPath<EnvironmentDetector, String?>,
        candidates: [String],
        apply: (String, String) -> Void
    ) async {
        guard let npmPath = findExecutable("npm") else {
            self[keyPath: error] = "Node.js (npm) not found — install Node.js first"
            return
        }
        self[keyPath: installing] = true
        self[keyPath: error] = nil
        defer { self[keyPath: installing] = false }

        let (_, stderr, exitCode) = await runProcessWithStatus(npmPath, arguments: ["install", "-g", package])
        if exitCode != 0 {
            self[keyPath: error] = stderr.isEmpty ? "Install failed (exit \(exitCode))" : String(stderr.prefix(200))
            return
        }
        // Re-detect
        await detectCLI(override: "", candidates: candidates, apply: apply)
    }

    private func installGoCLI(
        installing: ReferenceWritableKeyPath<EnvironmentDetector, Bool>,
        error: ReferenceWritableKeyPath<EnvironmentDetector, String?>,
        candidates: [String],
        apply: (String, String) -> Void
    ) async {
        guard let goPath = findExecutable("go") else {
            self[keyPath: error] = "Go not found — install Go first"
            return
        }
        self[keyPath: installing] = true
        self[keyPath: error] = nil
        defer { self[keyPath: installing] = false }

        let (_, stderr, exitCode) = await runProcessWithStatus(goPath, arguments: ["install", "github.com/opencode-ai/opencode@latest"])
        if exitCode != 0 {
            self[keyPath: error] = stderr.isEmpty ? "Install failed (exit \(exitCode))" : String(stderr.prefix(200))
            return
        }
        await detectCLI(override: "", candidates: candidates, apply: apply)
    }

    private func installBrewCLI(
        formula: String, isCask: Bool,
        installing: ReferenceWritableKeyPath<EnvironmentDetector, Bool>,
        error: ReferenceWritableKeyPath<EnvironmentDetector, String?>,
        candidates: [String],
        apply: (String, String) -> Void
    ) async {
        guard let brewPath = findBrewPath() else {
            self[keyPath: error] = "Homebrew not found — install Homebrew first"
            return
        }
        self[keyPath: installing] = true
        self[keyPath: error] = nil
        defer { self[keyPath: installing] = false }

        var args = ["install"]
        if isCask { args.append("--cask") }
        args.append(formula)

        let (stdout, stderr, exitCode) = await runProcessWithStatus(brewPath, arguments: args)
        if exitCode != 0 {
            // Homebrew cask writes success to stderr, check combined
            let combined = stdout + " " + stderr
            let isSuccess = combined.contains("successfully installed")
                || combined.contains("was successfully installed")
                || combined.contains("Pouring")
                || combined.contains("Moving App")
                || combined.contains("is already installed")
            if !isSuccess {
                self[keyPath: error] = stderr.isEmpty ? "Install failed (exit \(exitCode))" : String(stderr.prefix(200))
                return
            }
        }
        await detectCLI(override: "", candidates: candidates, apply: apply)
    }

    private func installPipCLI(
        installing: ReferenceWritableKeyPath<EnvironmentDetector, Bool>,
        error: ReferenceWritableKeyPath<EnvironmentDetector, String?>,
        candidates: [String],
        apply: (String, String) -> Void
    ) async {
        guard let pip3Path = findExecutable("pip3") else {
            self[keyPath: error] = "Python 3 (pip3) not found — install Python 3 first"
            return
        }
        self[keyPath: installing] = true
        self[keyPath: error] = nil
        defer { self[keyPath: installing] = false }

        let (_, stderr, exitCode) = await runProcessWithStatus(pip3Path, arguments: ["install", "mlx-lm"])
        if exitCode != 0 {
            self[keyPath: error] = stderr.isEmpty ? "Install failed (exit \(exitCode))" : String(stderr.prefix(200))
            return
        }
        await detectCLI(override: "", candidates: candidates, versionArgs: ["--help"], apply: apply)
    }

    // MARK: - Utility

    /// Find an executable on common PATH locations
    func findExecutable(_ name: String) -> String? {
        let searchPaths = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/bin/\(name)",
            "\(Self.home)/.local/bin/\(name)",
            "\(Self.home)/.npm-global/bin/\(name)",
            "\(Self.home)/go/bin/\(name)",
        ]
        for candidate in searchPaths {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Find Homebrew binary path
    func findBrewPath() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Run a process and return (stdout, stderr, exitCode)
    private func runProcessWithStatus(_ executablePath: String, arguments: [String]) async -> (String, String, Int32) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            var env = ProcessInfo.processInfo.environment
            // Ensure common paths are available
            let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(Self.home)/.local/bin", "\(Self.home)/go/bin"]
            let currentPath = env["PATH"] ?? "/usr/bin:/bin"
            let missingPaths = extraPaths.filter { !currentPath.contains($0) }
            if !missingPaths.isEmpty {
                env["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
            }
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: (out, err, proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ("", error.localizedDescription, -1))
            }
        }
    }
}
