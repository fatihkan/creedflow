import Foundation
import GRDB

// MARK: - Coder Branch Handler

extension Orchestrator {

    func handleCoderCompletion(task: AgentTask) async {
        // Check if this coder task is a deployment fix task — if so, handle redeploy
        let isDeployFix = await checkAndRedeployIfFixTask(task)
        if isDeployFix { return }  // Deploy fix tasks don't need review

        // Re-read task from DB to get current branchName and result
        // (the parameter is a stale copy from before setupCoderBranch set branchName)
        let currentTask = (try? await dbQueue.read { db in
            try AgentTask.fetchOne(db, id: task.id)
        }) ?? task

        // Commit + push + create PR targeting dev via branch manager
        let project = try? await dbQueue.read { db in
            try Project.fetchOne(db, id: currentTask.projectId)
        }
        if let project, !project.directoryPath.isEmpty {
            _ = await branchManager.handleCoderBranchCompletion(task: currentTask, in: project.directoryPath)
        }

        // Always queue reviewer task for non-deploy-fix coder completions
        let reviewDescription: String
        if let branch = currentTask.branchName {
            reviewDescription = "Review the code changes in branch \(branch) for task: \(currentTask.title)"
        } else {
            reviewDescription = "Review the code changes for task: \(currentTask.title)\n\nResult:\n\(currentTask.result?.prefix(2000) ?? "No output")"
        }

        try? await dbQueue.write { [currentTask] db in
            let reviewTask = AgentTask(
                projectId: currentTask.projectId,
                featureId: currentTask.featureId,
                agentType: .reviewer,
                title: "Review: \(currentTask.title)",
                description: reviewDescription,
                priority: currentTask.priority + 1,
                branchName: currentTask.branchName
            )
            try reviewTask.insert(db)

            let dep = TaskDependency(taskId: reviewTask.id, dependsOnTaskId: currentTask.id)
            try dep.insert(db)
        }
    }
}
