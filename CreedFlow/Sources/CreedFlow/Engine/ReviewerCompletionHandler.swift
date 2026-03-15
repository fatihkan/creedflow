import Foundation
import GRDB

// MARK: - Reviewer Completion Handler

extension Orchestrator {

    /// Parse reviewer JSON output and create a Review record
    func handleReviewerCompletion(task: AgentTask, result: AgentResult) async {
        guard let output = result.output else {
            try? await logError(taskId: task.id, agent: .reviewer, message: "Reviewer returned no output")
            try? await taskQueue.fail(task, error: "Reviewer returned no output")
            return
        }

        guard let data = extractJSON(from: output) else {
            try? await logError(taskId: task.id, agent: .reviewer, message: "Could not extract JSON from reviewer output: \(output.prefix(200))")
            try? await taskQueue.fail(task, error: "Could not extract structured review from output")
            return
        }

        struct ReviewerOutput: Decodable {
            let score: Double
            let verdict: String
            let summary: String
            let issues: FlexibleStringField?
            let suggestions: FlexibleStringField?
            let securityNotes: FlexibleStringField?
        }

        /// Decodes either a String or [String] into a single joined String
        struct FlexibleStringField: Decodable {
            let value: String

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let str = try? container.decode(String.self) {
                    value = str
                } else if let arr = try? container.decode([String].self) {
                    value = arr.joined(separator: "\n")
                } else {
                    value = ""
                }
            }
        }

        do {
            let parsed = try JSONDecoder().decode(ReviewerOutput.self, from: data)

            let verdict: Review.Verdict
            switch parsed.verdict.lowercased() {
            case "pass": verdict = .pass
            case "needs_revision", "needsrevision", "needs-revision": verdict = .needsRevision
            default: verdict = .fail
            }

            // Insert review record
            try await dbQueue.write { db in
                let review = Review(
                    taskId: task.id,
                    score: parsed.score,
                    verdict: verdict,
                    summary: parsed.summary,
                    issues: parsed.issues?.value,
                    suggestions: parsed.suggestions?.value,
                    securityNotes: parsed.securityNotes?.value,
                    sessionId: result.sessionId,
                    costUSD: result.costUSD
                )
                try review.insert(db)

                // Backfill review score on prompt usage records for this project
                try PromptUsage
                    .filter(Column("projectId") == task.projectId)
                    .filter(Column("reviewScore") == nil)
                    .updateAll(db, Column("reviewScore").set(to: parsed.score))
            }

            // Find the original coder task (the one this review task depends on)
            // and update its status based on the verdict
            if verdict == .pass {
                // Auto-merge the feature PR into dev
                await mergeCoderPROnReviewPass(reviewTaskId: task.id, projectId: task.projectId)
            } else {
                let coderTaskStatus: AgentTask.Status = verdict == .needsRevision ? .needsRevision : .failed
                try await dbQueue.write { db in
                    // Find dependency: this reviewer task depends on a coder task
                    let deps = try TaskDependency
                        .filter(Column("taskId") == task.id)
                        .fetchAll(db)
                    for dep in deps {
                        var coderTask = try AgentTask.fetchOne(db, id: dep.dependsOnTaskId)
                        if coderTask?.agentType == .coder {
                            coderTask?.status = coderTaskStatus
                            coderTask?.updatedAt = Date()
                            try coderTask?.update(db)
                        }
                    }
                }
            }

            try? await logInfo(taskId: task.id, agent: .reviewer,
                             message: "Review completed: score=\(parsed.score), verdict=\(verdict.rawValue)")

            // Automation flows: evaluate review triggers
            let reviewTriggerType = verdict == .pass ? "review_passed" : "review_failed"
            await automationEngine.evaluateTrigger(
                type: reviewTriggerType,
                context: [
                    "projectId": task.projectId.uuidString,
                    "taskId": task.id.uuidString,
                    "score": String(parsed.score),
                    "verdict": verdict.rawValue,
                ]
            )

            // Telegram notification: review completed
            let reviewForNotification = Review(
                taskId: task.id, score: parsed.score, verdict: verdict,
                summary: parsed.summary, issues: parsed.issues?.value,
                suggestions: parsed.suggestions?.value, securityNotes: parsed.securityNotes?.value
            )
            await sendTelegramNotification(for: task) { telegram, project in
                await telegram.notifyReviewCompleted(review: reviewForNotification, task: task, project: project)
            }

        } catch {
            try? await logError(taskId: task.id, agent: .reviewer,
                              message: "Failed to parse reviewer output: \(error.localizedDescription)")
        }
    }

    /// When a review passes, find the coder task's PR and merge it into dev.
    func mergeCoderPROnReviewPass(reviewTaskId: UUID, projectId: UUID) async {
        do {
            // Find the coder task this review depends on
            let coderTask = try await dbQueue.read { db -> AgentTask? in
                let deps = try TaskDependency
                    .filter(Column("taskId") == reviewTaskId)
                    .fetchAll(db)
                for dep in deps {
                    if let task = try AgentTask.fetchOne(db, id: dep.dependsOnTaskId),
                       task.agentType == .coder, task.prNumber != nil {
                        return task
                    }
                }
                return nil
            }

            guard let coderTask, let prNumber = coderTask.prNumber else { return }

            let project = try await dbQueue.read { db in
                try Project.fetchOne(db, id: projectId)
            }
            guard let project, !project.directoryPath.isEmpty else { return }

            await branchManager.mergeFeatureToDev(prNumber: prNumber, in: project.directoryPath)
        } catch {
            // Best effort — logged inside branchManager
        }
    }
}
