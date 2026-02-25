import Foundation
import GRDB
import os.log

/// Handles actual local deployment execution — detects project type and runs via Docker or direct process.
actor LocalDeploymentService {
    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: "com.creedflow", category: "LocalDeploymentService")

    /// Tracks running processes by deployment ID so we can stop them later.
    private var runningProcesses: [UUID: Process] = [:]

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Project Type Detection

    enum DeployMethod: String {
        case docker
        case dockerCompose = "docker-compose"
        case direct
    }

    struct DetectedProject {
        let method: DeployMethod
        let buildCommand: String
        let runCommand: String
    }

    func detectProjectType(at directoryPath: String) -> DetectedProject {
        let fm = FileManager.default

        if fm.fileExists(atPath: "\(directoryPath)/docker-compose.yml")
            || fm.fileExists(atPath: "\(directoryPath)/docker-compose.yaml") {
            return DetectedProject(
                method: .dockerCompose,
                buildCommand: "docker-compose build",
                runCommand: "docker-compose up -d"
            )
        }

        if fm.fileExists(atPath: "\(directoryPath)/Dockerfile") {
            return DetectedProject(
                method: .docker,
                buildCommand: "", // built inline during deploy
                runCommand: ""
            )
        }

        if fm.fileExists(atPath: "\(directoryPath)/package.json") {
            return DetectedProject(
                method: .direct,
                buildCommand: "npm install",
                runCommand: "npm start"
            )
        }

        if fm.fileExists(atPath: "\(directoryPath)/go.mod") {
            return DetectedProject(
                method: .direct,
                buildCommand: "go build -o app .",
                runCommand: "./app"
            )
        }

        if fm.fileExists(atPath: "\(directoryPath)/Package.swift") {
            return DetectedProject(
                method: .direct,
                buildCommand: "swift build",
                runCommand: "swift run"
            )
        }

        if fm.fileExists(atPath: "\(directoryPath)/requirements.txt") {
            return DetectedProject(
                method: .direct,
                buildCommand: "pip install -r requirements.txt",
                runCommand: "python main.py"
            )
        }

        if fm.fileExists(atPath: "\(directoryPath)/Cargo.toml") {
            return DetectedProject(
                method: .direct,
                buildCommand: "cargo build --release",
                runCommand: "cargo run --release"
            )
        }

        if fm.fileExists(atPath: "\(directoryPath)/Makefile") {
            return DetectedProject(
                method: .direct,
                buildCommand: "",
                runCommand: "make run"
            )
        }

        // Fallback: try to find an executable or main file
        return DetectedProject(
            method: .direct,
            buildCommand: "",
            runCommand: "echo 'No recognized project type found'"
        )
    }

    /// Build a DetectedProject for a user-selected deploy method, inferring build/run commands from project files.
    private func buildDetectedProject(method: DeployMethod, at directoryPath: String) -> DetectedProject {
        switch method {
        case .docker:
            return DetectedProject(method: .docker, buildCommand: "", runCommand: "")
        case .dockerCompose:
            return DetectedProject(method: .dockerCompose, buildCommand: "docker-compose build", runCommand: "docker-compose up -d")
        case .direct:
            // Auto-detect the run command based on project files
            let auto = detectProjectType(at: directoryPath)
            return DetectedProject(method: .direct, buildCommand: auto.buildCommand, runCommand: auto.runCommand)
        }
    }

    // MARK: - Deploy

    /// Execute a deployment for the given project and deployment record.
    /// Returns combined stdout+stderr logs.
    func deploy(project: Project, deployment: Deployment, port: Int) async throws -> Deployment {
        var deployment = deployment
        let directoryPath = project.directoryPath

        // Use pre-set deploy method if specified, otherwise auto-detect
        let detected: DetectedProject
        if let presetMethod = deployment.deployMethod, let method = DeployMethod(rawValue: presetMethod) {
            detected = buildDetectedProject(method: method, at: directoryPath)
        } else {
            detected = detectProjectType(at: directoryPath)
        }

        let envName = deployment.environment.rawValue
        let safeName = project.name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        // Stop any previous deployment for the same project+environment
        await stopExistingDeployment(projectId: project.id, environment: deployment.environment)

        deployment.status = .inProgress
        deployment.deployMethod = detected.method.rawValue
        deployment.port = port
        try await updateDeployment(deployment)

        do {
            switch detected.method {
            case .docker:
                deployment = try await deployDocker(
                    deployment: deployment,
                    directoryPath: directoryPath,
                    imageName: "creedflow-\(safeName)-\(envName)",
                    containerName: "creedflow-\(safeName)-\(envName)",
                    port: port
                )
            case .dockerCompose:
                deployment = try await deployDockerCompose(
                    deployment: deployment,
                    directoryPath: directoryPath
                )
            case .direct:
                deployment = try await deployDirect(
                    deployment: deployment,
                    directoryPath: directoryPath,
                    detected: detected,
                    port: port
                )
            }

            deployment.status = .success
            deployment.completedAt = Date()
            try await updateDeployment(deployment)
            logger.info("Deployment \(deployment.id) succeeded via \(detected.method.rawValue)")

        } catch {
            deployment.status = .failed
            deployment.completedAt = Date()
            deployment.logs = (deployment.logs ?? "") + "\nError: \(error.localizedDescription)"
            try? await updateDeployment(deployment)
            logger.error("Deployment \(deployment.id) failed: \(error.localizedDescription)")
            throw error
        }

        return deployment
    }

    // MARK: - Docker Deployment

    private func deployDocker(
        deployment: Deployment,
        directoryPath: String,
        imageName: String,
        containerName: String,
        port: Int
    ) async throws -> Deployment {
        var deployment = deployment

        // Build image
        let buildLogs = try await runShell(
            "docker build -t \(imageName) .",
            in: directoryPath
        )

        // Remove existing container if any
        _ = try? await runShell(
            "docker rm -f \(containerName)",
            in: directoryPath
        )

        // Run container
        let runLogs = try await runShell(
            "docker run -d --name \(containerName) -p \(port):\(port) \(imageName)",
            in: directoryPath
        )

        let containerId = runLogs.trimmingCharacters(in: .whitespacesAndNewlines)
        deployment.containerId = String(containerId.prefix(12))
        deployment.logs = buildLogs + "\n" + runLogs
        return deployment
    }

    // MARK: - Docker Compose Deployment

    private func deployDockerCompose(
        deployment: Deployment,
        directoryPath: String
    ) async throws -> Deployment {
        var deployment = deployment

        // Stop existing
        _ = try? await runShell("docker-compose down", in: directoryPath)

        // Build and start
        let logs = try await runShell("docker-compose up -d --build", in: directoryPath)
        deployment.logs = logs
        return deployment
    }

    // MARK: - Direct Process Deployment

    private func deployDirect(
        deployment: Deployment,
        directoryPath: String,
        detected: DetectedProject,
        port: Int
    ) async throws -> Deployment {
        var deployment = deployment
        var logs = ""

        // Build step (if any)
        if !detected.buildCommand.isEmpty {
            let buildOutput = try await runShell(detected.buildCommand, in: directoryPath)
            logs += buildOutput + "\n"
        }

        // Run step — spawn as background process
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", detected.runCommand]
        process.currentDirectoryURL = URL(fileURLWithPath: directoryPath)
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PORT": "\(port)"],
            uniquingKeysWith: { _, new in new }
        )

        try process.run()

        let pid = process.processIdentifier
        deployment.processId = Int(pid)
        runningProcesses[deployment.id] = process

        // Give the process a moment to either start or crash
        try await Task.sleep(for: .milliseconds(500))

        if process.isRunning {
            logs += "Process started (PID \(pid)) on port \(port)\n"
        } else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            logs += output
            runningProcesses.removeValue(forKey: deployment.id)
            throw DeploymentError.processExitedEarly(exitCode: Int(process.terminationStatus), output: output)
        }

        deployment.logs = logs
        return deployment
    }

    // MARK: - Stop

    /// Stop a running deployment (kills Docker container or OS process).
    func stop(deployment: Deployment) async throws {
        if let containerId = deployment.containerId {
            _ = try? await runShell("docker rm -f \(containerId)", in: nil)
        }

        if let process = runningProcesses[deployment.id] {
            process.terminate()
            runningProcesses.removeValue(forKey: deployment.id)
        } else if let pid = deployment.processId {
            _ = try? await runShell("kill \(pid)", in: nil)
        }

        var updated = deployment
        updated.status = .rolledBack
        updated.completedAt = Date()
        updated.logs = (updated.logs ?? "") + "\nStopped by user"
        try await updateDeployment(updated)
    }

    // MARK: - Status

    /// Check if a deployment is still running.
    func isRunning(deployment: Deployment) async -> Bool {
        if let containerId = deployment.containerId {
            let output = (try? await runShell(
                "docker inspect -f '{{.State.Running}}' \(containerId)",
                in: nil
            )) ?? "false"
            return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        }

        if let process = runningProcesses[deployment.id] {
            return process.isRunning
        }

        if let pid = deployment.processId {
            let output = (try? await runShell("kill -0 \(pid) 2>/dev/null && echo alive", in: nil)) ?? ""
            return output.contains("alive")
        }

        return false
    }

    // MARK: - Helpers

    /// Stop existing deployments for the same project+environment.
    private func stopExistingDeployment(projectId: UUID, environment: Deployment.Environment) async {
        let existing = try? await dbQueue.read { db in
            try Deployment
                .filter(Column("projectId") == projectId)
                .filter(Column("environment") == environment.rawValue)
                .filter(Column("status") == Deployment.Status.success.rawValue)
                .fetchAll(db)
        }
        guard let existing else { return }
        for deployment in existing {
            try? await stop(deployment: deployment)
        }
    }

    private func updateDeployment(_ deployment: Deployment) async throws {
        try await dbQueue.write { [deployment] db in
            var d = deployment
            try d.update(db)
        }
    }

    /// Run a shell command synchronously and return its combined output.
    private func runShell(_ command: String, in directory: String?) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw DeploymentError.commandFailed(command: command, exitCode: Int(process.terminationStatus), output: output)
        }

        return output
    }
}

// MARK: - Errors

enum DeploymentError: LocalizedError {
    case commandFailed(command: String, exitCode: Int, output: String)
    case processExitedEarly(exitCode: Int, output: String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let code, let output):
            return "Command '\(cmd)' failed (exit \(code)): \(output.prefix(500))"
        case .processExitedEarly(let code, let output):
            return "Process exited early (exit \(code)): \(output.prefix(500))"
        }
    }
}
