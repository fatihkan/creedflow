import Foundation

/// Auto-detects installed developer tools (Claude CLI, gh CLI, git config)
/// for the setup wizard and settings display.
@Observable
final class EnvironmentDetector {
    var claudePath: String = ""
    var claudeVersion: String = ""
    var ghPath: String = ""
    var ghVersion: String = ""
    var gitUserName: String = ""
    var gitUserEmail: String = ""
    var isDetecting = false

    var claudeFound: Bool { !claudePath.isEmpty && !claudeVersion.isEmpty }
    var ghFound: Bool { !ghPath.isEmpty && !ghVersion.isEmpty }
    var gitConfigured: Bool { !gitUserName.isEmpty && !gitUserEmail.isEmpty }

    private static let claudeCandidates = [
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
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
