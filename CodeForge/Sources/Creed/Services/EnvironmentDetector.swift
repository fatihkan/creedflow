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

    // Dev tools
    var ghPath: String = ""
    var ghVersion: String = ""
    var gitUserName: String = ""
    var gitUserEmail: String = ""
    var isDetecting = false

    var claudeFound: Bool { !claudePath.isEmpty && !claudeVersion.isEmpty }
    var codexFound: Bool { !codexPath.isEmpty && !codexVersion.isEmpty }
    var geminiFound: Bool { !geminiPath.isEmpty && !geminiVersion.isEmpty }
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

    private static let ghCandidates = [
        "/usr/local/bin/gh",
        "/opt/homebrew/bin/gh",
    ]

    /// Auto-detect all tools using candidate paths
    func detectAll() async {
        await detectAll(claudeOverride: "", codexOverride: "", geminiOverride: "")
    }

    /// Detect all tools, preferring user-provided override paths when non-empty
    func detectAll(claudeOverride: String, codexOverride: String, geminiOverride: String) async {
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
            group.addTask { await self.detectCLI(override: "", candidates: Self.ghCandidates) { path, version in
                self.ghPath = path; self.ghVersion = version
            }}
            group.addTask { await self.detectGit() }
        }
    }

    // MARK: - Generic CLI Detection

    private func detectCLI(
        override: String,
        candidates: [String],
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
            let output = try await Process.run(resolved, arguments: ["--version"])
            let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? ""
            apply(resolved, version)
        } catch {
            apply(resolved, "")
        }
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
