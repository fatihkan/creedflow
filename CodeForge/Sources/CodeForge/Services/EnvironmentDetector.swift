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

    func detectAll() async {
        isDetecting = true
        defer { isDetecting = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.detectClaude() }
            group.addTask { await self.detectCodex() }
            group.addTask { await self.detectGemini() }
            group.addTask { await self.detectGh() }
            group.addTask { await self.detectGit() }
        }
    }

    // MARK: - Claude CLI

    private func detectClaude() async {
        for candidate in Self.claudeCandidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                claudePath = candidate
                break
            }
        }

        guard !claudePath.isEmpty else { return }

        do {
            let output = try await Process.run(claudePath, arguments: ["--version"])
            claudeVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            claudeVersion = ""
        }
    }

    // MARK: - Codex CLI

    private func detectCodex() async {
        for candidate in Self.codexCandidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                codexPath = candidate
                break
            }
        }

        guard !codexPath.isEmpty else { return }

        do {
            let output = try await Process.run(codexPath, arguments: ["--version"])
            codexVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? ""
        } catch {
            codexVersion = ""
        }
    }

    // MARK: - Gemini CLI

    private func detectGemini() async {
        for candidate in Self.geminiCandidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                geminiPath = candidate
                break
            }
        }

        guard !geminiPath.isEmpty else { return }

        do {
            let output = try await Process.run(geminiPath, arguments: ["--version"])
            geminiVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? ""
        } catch {
            geminiVersion = ""
        }
    }

    // MARK: - gh CLI

    private func detectGh() async {
        for candidate in Self.ghCandidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                ghPath = candidate
                break
            }
        }

        guard !ghPath.isEmpty else { return }

        do {
            let output = try await Process.run(ghPath, arguments: ["--version"])
            ghVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? ""
        } catch {
            ghVersion = ""
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
