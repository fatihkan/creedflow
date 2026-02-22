import Foundation
@testable import CodeForgeLib

func assertEq<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    guard a == b else {
        fatalError("Assertion failed: \(a) != \(b) \(msg) (\(file):\(line))")
    }
}
func assertTrue(_ v: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    guard v else { fatalError("Assertion failed: expected true \(msg) (\(file):\(line))") }
}
func assertNil<T>(_ v: T?, _ msg: String = "", file: String = #file, line: Int = #line) {
    guard v == nil else { fatalError("Assertion failed: expected nil, got \(v!) \(msg) (\(file):\(line))") }
}

enum NDJSONParserTests {
    static func runAll() {
        testCompleteSingleLine()
        testMultipleCompleteLines()
        testPartialLineBuffering()
        testChunkSplitMiddle()
        testEmptyLinesSkipped()
        testFlushReturnsRemainingBuffer()
        testFlushReturnsNilWhenEmpty()
        testFeedData()
        testRealisticStreamOutput()
        testParseSystemEvent()
        testParseResultEventWithCost()
        testUnknownEventType()
        testMalformedJSON()
        print("  NDJSONParserTests: 13/13 passed")
    }

    static func testCompleteSingleLine() {
        var parser = NDJSONParser()
        let lines = parser.feed("{\"type\":\"system\"}\n")
        assertEq(lines, ["{\"type\":\"system\"}"])
    }

    static func testMultipleCompleteLines() {
        var parser = NDJSONParser()
        let lines = parser.feed("{\"type\":\"system\"}\n{\"type\":\"result\"}\n")
        assertEq(lines.count, 2)
        assertEq(lines[0], "{\"type\":\"system\"}")
        assertEq(lines[1], "{\"type\":\"result\"}")
    }

    static func testPartialLineBuffering() {
        var parser = NDJSONParser()
        let lines1 = parser.feed("{\"type\":")
        assertTrue(lines1.isEmpty)

        let lines2 = parser.feed("\"system\"}\n")
        assertEq(lines2, ["{\"type\":\"system\"}"])
    }

    static func testChunkSplitMiddle() {
        var parser = NDJSONParser()

        let lines1 = parser.feed("{\"type\":\"system\",\"ses")
        assertTrue(lines1.isEmpty)

        let lines2 = parser.feed("sionId\":\"abc\"}\n{\"type\":\"res")
        assertEq(lines2, ["{\"type\":\"system\",\"sessionId\":\"abc\"}"])

        let lines3 = parser.feed("ult\"}\n")
        assertEq(lines3, ["{\"type\":\"result\"}"])
    }

    static func testEmptyLinesSkipped() {
        var parser = NDJSONParser()
        let lines = parser.feed("\n\n{\"type\":\"system\"}\n\n")
        assertEq(lines, ["{\"type\":\"system\"}"])
    }

    static func testFlushReturnsRemainingBuffer() {
        var parser = NDJSONParser()
        let lines = parser.feed("{\"type\":\"partial\"}")
        assertTrue(lines.isEmpty)

        let flushed = parser.flush()
        assertEq(flushed, "{\"type\":\"partial\"}")
    }

    static func testFlushReturnsNilWhenEmpty() {
        var parser = NDJSONParser()
        _ = parser.feed("{\"type\":\"system\"}\n")
        let flushed = parser.flush()
        assertNil(flushed)
    }

    static func testFeedData() {
        var parser = NDJSONParser()
        let data = "{\"type\":\"system\"}\n".data(using: .utf8)!
        let lines = parser.feed(data)
        assertEq(lines, ["{\"type\":\"system\"}"])
    }

    static func testRealisticStreamOutput() {
        var parser = NDJSONParser()

        let lines1 = parser.feed("{\"type\":\"system\",\"sessionId\":\"abc123\",\"tools\":[\"Read\",\"Write\"]}\n")
        assertEq(lines1.count, 1)

        let lines2 = parser.feed("{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}]},\"sessionId\":\"abc123\"}\n")
        assertEq(lines2.count, 1)

        let lines3 = parser.feed("{\"type\":\"result\",\"sessionId\":\"abc123\",\"result\":\"done\",\"durationMs\":1234}\n")
        assertEq(lines3.count, 1)
    }

    static func testParseSystemEvent() {
        let line = "{\"type\":\"system\",\"sessionId\":\"abc123\"}"
        let event = ClaudeStreamEvent.parse(from: line)

        if case .system(let sysEvent) = event {
            assertEq(sysEvent.sessionId, "abc123")
        } else {
            fatalError("Expected system event")
        }
    }

    static func testParseResultEventWithCost() {
        let line = "{\"type\":\"result\",\"sessionId\":\"abc\",\"result\":\"done\",\"durationMs\":500,\"cost\":{\"inputTokens\":100,\"outputTokens\":50,\"totalUsd\":0.001}}"
        let event = ClaudeStreamEvent.parse(from: line)

        if case .result(let res) = event {
            assertEq(res.sessionId, "abc")
            assertEq(res.durationMs, 500)
            assertEq(res.cost?.inputTokens, 100)
            assertEq(res.cost?.outputTokens, 50)
        } else {
            fatalError("Expected result event")
        }
    }

    static func testUnknownEventType() {
        let line = "{\"type\":\"unknown_type\",\"data\":123}"
        let event = ClaudeStreamEvent.parse(from: line)

        if case .unknown = event {
            // Expected
        } else {
            fatalError("Expected unknown event")
        }
    }

    static func testMalformedJSON() {
        let line = "not valid json at all"
        let event = ClaudeStreamEvent.parse(from: line)

        if case .unknown = event {
            // Expected
        } else {
            fatalError("Expected unknown event for malformed JSON")
        }
    }
}
