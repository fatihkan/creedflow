import Foundation
@testable import CreedFlowLib

enum ChainConditionTests {
    static func runAll() {
        testReviewScoreGtePass()
        testReviewScoreGteFail()
        testReviewVerdictEq()
        testReviewVerdictNeq()
        testOutputContains()
        testOutputNotContains()
        testStepSuccessTrue()
        testStepSuccessFalse()
        testDecodeFromJSON()
        testDecodeInvalidJSON()
        testCodableRoundTrip()
        print("  ChainConditionTests: 11/11 passed")
    }

    // MARK: - Review Score

    static func testReviewScoreGtePass() {
        let cond = ChainCondition(
            field: .reviewScore,
            op: .gte,
            value: .number(7.0)
        )
        let result = cond.evaluate(stepOutput: "some output", reviewScore: 8.5, reviewVerdict: "pass")
        assertTrue(result, "score 8.5 >= 7.0 should pass")
    }

    static func testReviewScoreGteFail() {
        let cond = ChainCondition(
            field: .reviewScore,
            op: .gte,
            value: .number(7.0)
        )
        let result = cond.evaluate(stepOutput: "some output", reviewScore: 5.5, reviewVerdict: "needsRevision")
        assertTrue(!result, "score 5.5 >= 7.0 should fail")
    }

    // MARK: - Review Verdict

    static func testReviewVerdictEq() {
        let cond = ChainCondition(
            field: .reviewVerdict,
            op: .eq,
            value: .string("pass")
        )
        assertTrue(cond.evaluate(stepOutput: nil, reviewScore: 8.0, reviewVerdict: "pass"))
        assertTrue(!cond.evaluate(stepOutput: nil, reviewScore: 5.0, reviewVerdict: "fail"))
    }

    static func testReviewVerdictNeq() {
        let cond = ChainCondition(
            field: .reviewVerdict,
            op: .neq,
            value: .string("fail")
        )
        assertTrue(cond.evaluate(stepOutput: nil, reviewScore: 8.0, reviewVerdict: "pass"))
        assertTrue(!cond.evaluate(stepOutput: nil, reviewScore: 3.0, reviewVerdict: "fail"))
    }

    // MARK: - Output Contains

    static func testOutputContains() {
        let cond = ChainCondition(
            field: .outputContains,
            op: .contains,
            value: .string("SUCCESS")
        )
        assertTrue(cond.evaluate(stepOutput: "Build SUCCESS completed", reviewScore: nil, reviewVerdict: nil))
        assertTrue(!cond.evaluate(stepOutput: "Build failed", reviewScore: nil, reviewVerdict: nil))
    }

    static func testOutputNotContains() {
        let cond = ChainCondition(
            field: .outputContains,
            op: .notContains,
            value: .string("error")
        )
        assertTrue(cond.evaluate(stepOutput: "All good", reviewScore: nil, reviewVerdict: nil))
        assertTrue(!cond.evaluate(stepOutput: "Found an Error in code", reviewScore: nil, reviewVerdict: nil))
    }

    // MARK: - Step Success

    static func testStepSuccessTrue() {
        let cond = ChainCondition(
            field: .stepSuccess,
            op: .eq,
            value: .bool(true)
        )
        assertTrue(cond.evaluate(stepOutput: "has output", reviewScore: nil, reviewVerdict: nil))
        assertTrue(!cond.evaluate(stepOutput: "", reviewScore: nil, reviewVerdict: nil))
        assertTrue(!cond.evaluate(stepOutput: nil, reviewScore: nil, reviewVerdict: nil))
    }

    static func testStepSuccessFalse() {
        let cond = ChainCondition(
            field: .stepSuccess,
            op: .eq,
            value: .bool(false)
        )
        assertTrue(cond.evaluate(stepOutput: "", reviewScore: nil, reviewVerdict: nil))
        assertTrue(!cond.evaluate(stepOutput: "has output", reviewScore: nil, reviewVerdict: nil))
    }

    // MARK: - JSON Decode

    static func testDecodeFromJSON() {
        let json = #"{"field":"reviewScore","op":"gte","value":7}"#
        let cond = ChainCondition.decode(from: json)
        assertTrue(cond != nil, "should decode valid JSON")
        assertEq(cond!.field, .reviewScore)
        assertEq(cond!.op, .gte)
        assertEq(cond!.value, .number(7.0))
    }

    static func testDecodeInvalidJSON() {
        let cond = ChainCondition.decode(from: "not json")
        assertTrue(cond == nil, "should return nil for invalid JSON")
    }

    // MARK: - Codable round-trip

    static func testCodableRoundTrip() {
        let original = ChainCondition(
            field: .outputContains,
            op: .contains,
            value: .string("deploy")
        )
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(ChainCondition.self, from: data)
        assertEq(original, decoded)
    }
}
