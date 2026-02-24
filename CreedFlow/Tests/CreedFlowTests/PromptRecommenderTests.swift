import Foundation
@testable import CreedFlowLib

enum PromptRecommenderTests {
    static func runAll() {
        testScoreWithNoUsages()
        testScoreWithAllCompleted()
        testScoreWithAllFailed()
        testScoreWithMixedOutcomes()
        testScoreWithReviewScores()
        testScoreWithHighUsageCount()
        testScoreUsageFactorCapsAtOne()
        testScoreNoOutcomesDefaultsHalf()
        testScoreNoReviewScoresDefaultsFive()
        testCategoryMapping()
        print("  PromptRecommenderTests: 10/10 passed")
    }

    // Helper to create PromptUsage with specific fields
    private static func usage(
        outcome: PromptUsage.Outcome? = nil,
        reviewScore: Double? = nil
    ) -> PromptUsage {
        PromptUsage(
            promptId: UUID(),
            outcome: outcome,
            reviewScore: reviewScore
        )
    }

    // MARK: - computeScore Tests

    static func testScoreWithNoUsages() {
        let score = PromptRecommender.computeScore(usages: [])
        assertEq(score, 0.2) // Base score for unused prompts
    }

    static func testScoreWithAllCompleted() {
        // 3 completed, no review scores
        // successRate = 1.0, avgReview = 5.0 (default), usageFactor = 3/10 = 0.3
        // score = (1.0 * 0.5) + (5.0/10 * 0.3) + (0.3 * 0.2) = 0.5 + 0.15 + 0.06 = 0.71
        let usages = [
            usage(outcome: .completed),
            usage(outcome: .completed),
            usage(outcome: .completed),
        ]
        let score = PromptRecommender.computeScore(usages: usages)
        assertApproxEq(score, 0.71, tolerance: 0.001)
    }

    static func testScoreWithAllFailed() {
        // 2 failed, no review scores
        // successRate = 0.0, avgReview = 5.0 (default), usageFactor = 2/10 = 0.2
        // score = (0.0 * 0.5) + (5.0/10 * 0.3) + (0.2 * 0.2) = 0 + 0.15 + 0.04 = 0.19
        let usages = [
            usage(outcome: .failed),
            usage(outcome: .failed),
        ]
        let score = PromptRecommender.computeScore(usages: usages)
        assertApproxEq(score, 0.19, tolerance: 0.001)
    }

    static func testScoreWithMixedOutcomes() {
        // 2 completed, 2 failed → successRate = 0.5
        // avgReview = 5.0 (default), usageFactor = 4/10 = 0.4
        // score = (0.5 * 0.5) + (5.0/10 * 0.3) + (0.4 * 0.2) = 0.25 + 0.15 + 0.08 = 0.48
        let usages = [
            usage(outcome: .completed),
            usage(outcome: .completed),
            usage(outcome: .failed),
            usage(outcome: .failed),
        ]
        let score = PromptRecommender.computeScore(usages: usages)
        assertApproxEq(score, 0.48, tolerance: 0.001)
    }

    static func testScoreWithReviewScores() {
        // 2 completed with review scores 8.0 and 6.0 → avg = 7.0
        // successRate = 1.0, usageFactor = 2/10 = 0.2
        // score = (1.0 * 0.5) + (7.0/10 * 0.3) + (0.2 * 0.2) = 0.5 + 0.21 + 0.04 = 0.75
        let usages = [
            usage(outcome: .completed, reviewScore: 8.0),
            usage(outcome: .completed, reviewScore: 6.0),
        ]
        let score = PromptRecommender.computeScore(usages: usages)
        assertApproxEq(score, 0.75, tolerance: 0.001)
    }

    static func testScoreWithHighUsageCount() {
        // 10 completed, perfect reviews (10.0)
        // successRate = 1.0, avgReview = 10.0, usageFactor = min(10/10, 1) = 1.0
        // score = (1.0 * 0.5) + (10.0/10 * 0.3) + (1.0 * 0.2) = 0.5 + 0.3 + 0.2 = 1.0
        var usages: [PromptUsage] = []
        for _ in 0..<10 {
            usages.append(usage(outcome: .completed, reviewScore: 10.0))
        }
        let score = PromptRecommender.computeScore(usages: usages)
        assertApproxEq(score, 1.0, tolerance: 0.001)
    }

    static func testScoreUsageFactorCapsAtOne() {
        // 20 completed → usageFactor = min(20/10, 1) = 1.0 (capped)
        var usages: [PromptUsage] = []
        for _ in 0..<20 {
            usages.append(usage(outcome: .completed))
        }
        let score = PromptRecommender.computeScore(usages: usages)
        // successRate = 1.0, avgReview = 5.0 (default), usageFactor = 1.0
        // score = 0.5 + 0.15 + 0.2 = 0.85
        assertApproxEq(score, 0.85, tolerance: 0.001)
    }

    static func testScoreNoOutcomesDefaultsHalf() {
        // Usages exist but no outcome → successRate defaults to 0.5
        // usageFactor = 1/10 = 0.1
        // score = (0.5 * 0.5) + (5.0/10 * 0.3) + (0.1 * 0.2) = 0.25 + 0.15 + 0.02 = 0.42
        let usages = [usage()]
        let score = PromptRecommender.computeScore(usages: usages)
        assertApproxEq(score, 0.42, tolerance: 0.001)
    }

    static func testScoreNoReviewScoresDefaultsFive() {
        // All completed but no review scores → avgReview defaults to 5.0
        let usages = [
            usage(outcome: .completed),
            usage(outcome: .completed),
        ]
        let score = PromptRecommender.computeScore(usages: usages)
        // successRate = 1.0, avgReview = 5.0, usageFactor = 0.2
        // score = 0.5 + 0.15 + 0.04 = 0.69
        assertApproxEq(score, 0.69, tolerance: 0.001)
    }

    // MARK: - Category Mapping

    static func testCategoryMapping() {
        assertEq(PromptRecommender.category(for: .analyzer), "analyzer")
        assertEq(PromptRecommender.category(for: .coder), "coder")
        assertEq(PromptRecommender.category(for: .reviewer), "reviewer")
        assertEq(PromptRecommender.category(for: .tester), "tester")
        assertEq(PromptRecommender.category(for: .devops), "devops")
        assertEq(PromptRecommender.category(for: .monitor), "monitor")
        assertEq(PromptRecommender.category(for: .contentWriter), "content")
        assertEq(PromptRecommender.category(for: .designer), "design")
        assertEq(PromptRecommender.category(for: .imageGenerator), "image")
        assertEq(PromptRecommender.category(for: .videoEditor), "video")
        assertEq(PromptRecommender.category(for: .publisher), "publishing")
    }
}

// MARK: - Approximate Equality Helper

func assertApproxEq(_ a: Double, _ b: Double, tolerance: Double, file: String = #file, line: Int = #line) {
    guard abs(a - b) <= tolerance else {
        fatalError("Assertion failed: \(a) ≈ \(b) (tolerance \(tolerance)) (\(file):\(line))")
    }
}
