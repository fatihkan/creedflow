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

    /// Editor candidates: (display name, CLI command name, candidate paths)
    private static let editorCandidates: [(name: String, command: String, paths: [String])] = [
        ("VS Code", "code", [
            "/usr/local/bin/code",
            "\(home)/.local/bin/code",
            "/opt/homebrew/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
        ]),
        ("Cursor", "cursor", [
            "/usr/local/bin/cursor",
            "\(home)/.local/bin/cursor",
            "/opt/homebrew/bin/cursor",
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
        ]),
        ("Zed", "zed", [
            "/usr/local/bin/zed",
            "\(home)/.local/bin/zed",
            "/opt/homebrew/bin/zed",
            "/Applications/Zed.app/Contents/MacOS/cli/zed",
        ]),
        ("Sublime Text", "subl", [
            "/usr/local/bin/subl",
            "/opt/homebrew/bin/subl",
            "/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl",
        ]),
        ("Xcode", "xed", ["/usr/bin/xed"]),
        ("Windsurf", "windsurf", [
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
            for candidate in editor.paths {
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    found.append((name: editor.name, command: editor.command, path: candidate))
                    break
                }
            }
        }
        detectedEditors = found
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
}
