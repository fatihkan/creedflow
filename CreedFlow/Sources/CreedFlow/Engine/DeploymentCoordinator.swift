import Foundation
import GRDB

// MARK: - Deployment Coordinator

extension Orchestrator {

    // MARK: - Deployment Auto-Recovery

    /// Check if a completed coder task is linked to a failed deployment as a fix task.
    /// If the coder task passed, reset the deployment to pending and re-trigger it.
    /// Returns true if this task was a deployment fix task.
    @discardableResult
    func checkAndRedeployIfFixTask(_ task: AgentTask) async -> Bool {
        // Find any deployment whose fixTaskId matches this task
        let deployment = try? await dbQueue.read { db in
            try Deployment
                .filter(Column("fixTaskId") == task.id)
                .fetchOne(db)
        }
        guard var deployment else { return false }

        // Re-read task from DB to get current status (parameter may be stale)
        let currentTask = try? await dbQueue.read { db in
            try AgentTask.fetchOne(db, id: task.id)
        }
        let taskStatus = currentTask?.status ?? task.status

        if taskStatus == .passed {
            // Fix succeeded — reset deployment to pending so the Orchestrator re-deploys
            try? await logInfo(
                taskId: task.id,
                agent: .coder,
                message: "Deployment fix passed — re-queuing deployment \(deployment.id) for redeploy"
            )

            deployment.status = .pending
            deployment.completedAt = nil
            deployment.logs = (deployment.logs ?? "") + "\n--- Fix applied (task \(task.id)) — retrying deployment ---\n"
            let updated = deployment

            try? await dbQueue.write { db in
                var d = updated
                try d.update(db)
            }

            // Queue a new DevOps task to actually run the deployment again
            let project = try? await dbQueue.read { db in
                try Project.fetchOne(db, id: deployment.projectId)
            }

            try? await dbQueue.write { [deployment] db in
                let redeployTask = AgentTask(
                    projectId: deployment.projectId,
                    agentType: .devops,
                    title: "Redeploy: \(project?.name ?? "project") (\(deployment.environment.rawValue))",
                    description: """
                        Retry deployment after fix was applied.
                        Previous failure was fixed by task \(task.id).
                        Deployment ID: \(deployment.id)
                        Method: \(deployment.deployMethod ?? "auto-detect")
                        Port: \(deployment.port.map(String.init) ?? "auto")
                        """,
                    priority: 10
                )
                try redeployTask.insert(db)

                // Redeploy depends on the fix task being done
                let dep = TaskDependency(taskId: redeployTask.id, dependsOnTaskId: task.id)
                try dep.insert(db)
            }
        } else {
            // Fix task itself failed — spawn another fix attempt (if under limit)
            let failLogs = task.errorMessage ?? task.result ?? "Coder fix task failed with no output"
            try? await logError(
                taskId: task.id,
                agent: .coder,
                message: "Deployment fix task failed — will attempt another fix if under limit"
            )
            await spawnDeploymentFixTask(deployment: deployment, errorLogs: failLogs)
        }

        return true
    }

    /// Maximum number of auto-fix attempts per deployment before giving up.
    static let maxDeployAutoFixAttempts = 3

    /// Update deployment status after devops task completes, then run actual deployment (#30).
    /// If the deployment fails, automatically creates a Coder fix task using the error logs.
    func handleDevOpsCompletion(task: AgentTask, result: AgentResult) async {
        do {
            // Re-read task from DB to get current status (the parameter is a stale copy
            // from before MultiBackendRunner updated it to .passed/.failed)
            let currentTask = try await dbQueue.read { db in
                try AgentTask.fetchOne(db, id: task.id)
            }
            let taskStatus = currentTask?.status ?? task.status

            // Find the pending deployment for this project
            let deployment = try await dbQueue.read { db in
                try Deployment
                    .filter(Column("projectId") == task.projectId)
                    .filter(Column("status") == Deployment.Status.pending.rawValue)
                    .order(Column("createdAt").desc)
                    .fetchOne(db)
            }

            guard var deployment else {
                try? await logInfo(taskId: task.id, agent: .devops,
                                  message: "No pending deployment found — skipping local deploy")
                return
            }

            // If devops agent task failed, mark deployment as failed and spawn fix task
            guard taskStatus == .passed else {
                let failLogs = task.errorMessage ?? result.output ?? "DevOps task failed with no output"
                deployment.status = .failed
                deployment.completedAt = Date()
                deployment.logs = failLogs
                let failedDeployment = deployment
                try await dbQueue.write { db in
                    var d = failedDeployment
                    try d.update(db)
                }
                await spawnDeploymentFixTask(deployment: deployment, errorLogs: failLogs)
                return
            }

            // Resolve project for directory path
            let project = try await dbQueue.read { db in
                try Project.fetchOne(db, id: task.projectId)
            }
            guard let project else { return }

            let port: Int
            if let existingPort = deployment.port {
                port = existingPort
            } else {
                switch deployment.environment {
                case .production: port = 3000
                case .staging: port = 3001
                case .development: port = 3002
                }
            }
            deployment.port = port

            // Persist port assignment before deploying
            try await dbQueue.write { db in
                var d = deployment
                try d.update(db)
            }

            // Run actual local deployment
            _ = try await localDeployService.deploy(
                project: project,
                deployment: deployment,
                port: port
            )

            // Mark deployment as successful — re-read from DB to avoid stale overwrites
            try await dbQueue.write { db in
                guard var d = try Deployment.fetchOne(db, id: deployment.id) else { return }
                d.status = .success
                d.completedAt = Date()
                try d.update(db)
            }

            try? await logInfo(taskId: task.id, agent: .devops,
                             message: "Local deployment completed on port \(port)")

            // Automation flows: evaluate deploy_success trigger
            await automationEngine.evaluateTrigger(
                type: "deploy_success",
                context: [
                    "projectId": task.projectId.uuidString,
                    "environment": deployment.environment.rawValue,
                    "deploymentId": deployment.id.uuidString,
                ]
            )

            // After successful staging deploy, promote staging → main
            if deployment.environment == .staging {
                _ = await branchManager.promoteStagingToMain(
                    projectId: project.id,
                    version: deployment.version,
                    in: project.directoryPath
                )
            }

        } catch {
            // LocalDeploymentService already marks the deployment as .failed in its own
            // catch block before re-throwing, so we don't need to update the status here.
            // Just log and spawn the fix task.
            try? await logError(taskId: task.id, agent: .devops,
                              message: "Failed to deploy: \(error.localizedDescription)")

            // Automation flows: evaluate deploy_failed trigger
            await automationEngine.evaluateTrigger(
                type: "deploy_failed",
                context: [
                    "projectId": task.projectId.uuidString,
                    "error": error.localizedDescription,
                ]
            )

            await handleLocalDeployFailure(task: task, error: error)
        }
    }

    /// When local deployment fails, find the deployment record and spawn a coder fix task.
    func handleLocalDeployFailure(task: AgentTask, error: Error) async {
        do {
            let deployment = try await dbQueue.read { db in
                try Deployment
                    .filter(Column("projectId") == task.projectId)
                    .filter(Column("status") == Deployment.Status.failed.rawValue)
                    .order(Column("createdAt").desc)
                    .fetchOne(db)
            }
            guard let deployment else { return }
            await spawnDeploymentFixTask(deployment: deployment, errorLogs: error.localizedDescription)
        } catch {
            // Non-critical — already logged above
        }
    }

    /// Create a Coder task to fix a failed deployment. The task description includes the full error logs
    /// so the coder agent has context to diagnose and fix the issue.
    func spawnDeploymentFixTask(deployment: Deployment, errorLogs: String) async {
        // Guard: don't exceed max auto-fix attempts
        guard deployment.autoFixAttempts < Self.maxDeployAutoFixAttempts else {
            try? await dbQueue.write { [deployment] db in
                let log = AgentLog(
                    taskId: deployment.fixTaskId ?? UUID(),
                    agentType: .devops,
                    level: .error,
                    message: "Deployment \(deployment.id) exhausted \(Self.maxDeployAutoFixAttempts) auto-fix attempts — manual intervention required"
                )
                try log.insert(db)
            }
            return
        }

        // Guard: don't create duplicate fix task if one already exists and is still active
        if let existingFixId = deployment.fixTaskId {
            let existingTask = try? await dbQueue.read { db in
                try AgentTask.fetchOne(db, id: existingFixId)
            }
            if let existingTask, existingTask.status == .queued || existingTask.status == .inProgress {
                return // Fix task already in flight
            }
        }

        // Fetch project name for a descriptive title
        let projectName = (try? await dbQueue.read { db in
            try Project.fetchOne(db, id: deployment.projectId)?.name
        }) ?? "Unknown"

        let truncatedLogs = String(errorLogs.prefix(3000))
        let attempt = deployment.autoFixAttempts + 1

        do {
            let fixTask = AgentTask(
                projectId: deployment.projectId,
                agentType: .coder,
                title: "Fix deployment failure: \(projectName) (\(deployment.environment.rawValue)) [attempt \(attempt)]",
                description: """
                    The deployment for project "\(projectName)" to \(deployment.environment.rawValue) has failed.
                    Deployment method: \(deployment.deployMethod ?? "unknown")
                    Port: \(deployment.port.map(String.init) ?? "N/A")

                    ERROR LOGS:
                    \(truncatedLogs)

                    INSTRUCTIONS:
                    1. Analyze the error logs above to identify the root cause.
                    2. Fix the issue in the project source code (Dockerfile, package.json, config files, source code, etc.).
                    3. Ensure the project can build and run successfully.
                    4. Do NOT attempt to deploy — deployment will be triggered automatically after this fix passes.
                    """,
                priority: 10 // High priority — deployment is broken
            )

            try await dbQueue.write { [fixTask, deployment] db in
                var task = fixTask
                try task.insert(db)

                // Link fix task to deployment and increment attempt counter
                var d = deployment
                d.fixTaskId = task.id
                d.autoFixAttempts += 1
                try d.update(db)
            }

            try? await logInfo(
                taskId: fixTask.id,
                agent: .coder,
                message: "Auto-created fix task for failed deployment \(deployment.id) (attempt \(attempt)/\(Self.maxDeployAutoFixAttempts))"
            )
        } catch {
            try? await logError(
                taskId: UUID(),
                agent: .devops,
                message: "Failed to create deployment fix task: \(error.localizedDescription)"
            )
        }
    }

    /// Backfill PromptUsage outcome when a project reaches a terminal status.
    func backfillPromptUsageOutcome(projectId: UUID, outcome: PromptUsage.Outcome) async {
        _ = try? await dbQueue.write { db in
            try PromptUsage
                .filter(Column("projectId") == projectId)
                .filter(Column("outcome") == nil)
                .updateAll(db, Column("outcome").set(to: outcome.rawValue))
        }
    }

    /// Check if all tasks for a project are done and update project status + prompt usage accordingly.
    func checkProjectCompletion(projectId: UUID) async {
        do {
            let (allDone, anyFailed) = try await dbQueue.read { db -> (Bool, Bool) in
                let tasks = try AgentTask
                    .filter(Column("projectId") == projectId)
                    .filter(Column("archivedAt") == nil)
                    .fetchAll(db)
                let pending = tasks.contains { $0.status == .queued || $0.status == .inProgress }
                let failed = tasks.contains { $0.status == .failed }
                return (!pending, failed)
            }
            guard allDone else { return }

            // Set project completedAt if not already set
            try await dbQueue.write { db in
                guard var project = try Project.fetchOne(db, id: projectId) else { return }
                if project.completedAt == nil {
                    project.completedAt = Date()
                    if !anyFailed {
                        project.status = .completed
                    }
                    project.updatedAt = Date()
                    try project.update(db)
                }
            }

            let outcome: PromptUsage.Outcome = anyFailed ? .failed : .completed
            await backfillPromptUsageOutcome(projectId: projectId, outcome: outcome)
        } catch {
            // Non-critical — log and continue
        }
    }
}
