import Foundation

/// Loads the user's login shell environment so that CLI tools (Homebrew, npm, etc.)
/// are discoverable when running as a .app bundle.
/// macOS .app bundles get a minimal PATH (/usr/bin:/bin). This class runs the user's
/// shell in login mode to capture the full PATH and other env vars.
package final class ShellEnvironment: @unchecked Sendable {
    package static let shared = ShellEnvironment()

    /// The full environment from the user's login shell
    private(set) var environment: [String: String]

    private init() {
        self.environment = Self.loadShellEnvironment()
    }

    /// Apply the shell environment to the current process so all child processes inherit it.
    package func apply() {
        for (key, value) in environment {
            setenv(key, value, 1)
        }
    }

    private static func loadShellEnvironment() -> [String: String] {
        // Start with the current (possibly minimal) environment
        var env = ProcessInfo.processInfo.environment

        // Determine the user's login shell
        let shell = env["SHELL"] ?? "/bin/zsh"

        // Run the shell in login mode to source profile files,
        // then print the environment
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l = login shell (sources ~/.zprofile, ~/.zshrc, etc.)
        // -c = run command
        process.arguments = ["-l", "-c", "env"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            for line in output.components(separatedBy: "\n") {
                guard let eqIndex = line.firstIndex(of: "=") else { continue }
                let key = String(line[line.startIndex..<eqIndex])
                let value = String(line[line.index(after: eqIndex)...])
                // Only update PATH and common tool-related vars
                if key == "PATH" || key.hasPrefix("HOMEBREW") ||
                   key.hasSuffix("_API_KEY") || key.hasSuffix("_TOKEN") ||
                   key == "GOPATH" || key == "CARGO_HOME" || key == "RUSTUP_HOME" ||
                   key == "NVM_DIR" || key == "PYENV_ROOT" || key == "VOLTA_HOME" ||
                   key == "GEM_HOME" || key == "ANDROID_HOME" || key == "JAVA_HOME" {
                    env[key] = value
                }
            }
        } catch {
            // Fallback: manually add common paths
            let fallbackPaths = [
                "/opt/homebrew/bin",
                "/opt/homebrew/sbin",
                "/usr/local/bin",
                "/usr/local/sbin",
                NSHomeDirectory() + "/.cargo/bin",
                NSHomeDirectory() + "/.local/bin",
                NSHomeDirectory() + "/.nvm/versions/node/*/bin",
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin",
            ]
            let currentPath = env["PATH"] ?? "/usr/bin:/bin"
            let allPaths = fallbackPaths + currentPath.components(separatedBy: ":")
            let uniquePaths = NSOrderedSet(array: allPaths).array as? [String] ?? allPaths
            env["PATH"] = uniquePaths.joined(separator: ":")
        }

        return env
    }
}
