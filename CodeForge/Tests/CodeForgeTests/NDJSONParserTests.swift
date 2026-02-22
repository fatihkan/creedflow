import XCTest
@testable import CodeForge

final class NDJSONParserTests: XCTestCase {

    func testCompleteSingleLine() {
        var parser = NDJSONParser()
        let lines = parser.feed("{\"type\":\"system\"}\n")
        XCTAssertEqual(lines, ["{\"type\":\"system\"}"])
    }

    func testMultipleCompleteLines() {
        var parser = NDJSONParser()
        let lines = parser.feed("{\"type\":\"system\"}\n{\"type\":\"result\"}\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "{\"type\":\"system\"}")
        XCTAssertEqual(lines[1], "{\"type\":\"result\"}")
    }

    func testPartialLineBuffering() {
        var parser = NDJSONParser()
        let lines1 = parser.feed("{\"type\":")
        XCTAssertTrue(lines1.isEmpty)

        let lines2 = parser.feed("\"system\"}\n")
        XCTAssertEqual(lines2, ["{\"type\":\"system\"}"])
    }

    func testChunkSplitMiddle() {
        var parser = NDJSONParser()

        let lines1 = parser.feed("{\"type\":\"system\",\"ses")
        XCTAssertTrue(lines1.isEmpty)

        let lines2 = parser.feed("sionId\":\"abc\"}\n{\"type\":\"res")
        XCTAssertEqual(lines2, ["{\"type\":\"system\",\"sessionId\":\"abc\"}"])

        let lines3 = parser.feed("ult\"}\n")
        XCTAssertEqual(lines3, ["{\"type\":\"result\"}"])
    }

    func testEmptyLinesSkipped() {
        var parser = NDJSONParser()
        let lines = parser.feed("\n\n{\"type\":\"system\"}\n\n")
        XCTAssertEqual(lines, ["{\"type\":\"system\"}"])
    }

    func testFlushReturnsRemainingBuffer() {
        var parser = NDJSONParser()
        let lines = parser.feed("{\"type\":\"partial\"}")
        XCTAssertTrue(lines.isEmpty)

        let flushed = parser.flush()
        XCTAssertEqual(flushed, "{\"type\":\"partial\"}")
    }

    func testFlushReturnsNilWhenEmpty() {
        var parser = NDJSONParser()
        _ = parser.feed("{\"type\":\"system\"}\n")
        let flushed = parser.flush()
        XCTAssertNil(flushed)
    }

    func testFeedData() {
        var parser = NDJSONParser()
        let data = "{\"type\":\"system\"}\n".data(using: .utf8)!
        let lines = parser.feed(data)
        XCTAssertEqual(lines, ["{\"type\":\"system\"}"])
    }

    func testRealisticStreamOutput() {
        var parser = NDJSONParser()

        let chunk1 = "{\"type\":\"system\",\"sessionId\":\"abc123\",\"tools\":[\"Read\",\"Write\"]}\n"
        let lines1 = parser.feed(chunk1)
        XCTAssertEqual(lines1.count, 1)

        let chunk2 = "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}]},\"sessionId\":\"abc123\"}\n"
        let lines2 = parser.feed(chunk2)
        XCTAssertEqual(lines2.count, 1)

        let chunk3 = "{\"type\":\"result\",\"sessionId\":\"abc123\",\"result\":\"done\",\"durationMs\":1234}\n"
        let lines3 = parser.feed(chunk3)
        XCTAssertEqual(lines3.count, 1)
    }

    func testParseSystemEvent() {
        let line = "{\"type\":\"system\",\"sessionId\":\"abc123\"}"
        let event = ClaudeStreamEvent.parse(from: line)

        if case .system(let sysEvent) = event {
            XCTAssertEqual(sysEvent.sessionId, "abc123")
        } else {
            XCTFail("Expected system event")
        }
    }

    func testParseResultEventWithCost() {
        let line = "{\"type\":\"result\",\"sessionId\":\"abc\",\"result\":\"done\",\"durationMs\":500,\"cost\":{\"inputTokens\":100,\"outputTokens\":50,\"totalUsd\":0.001}}"
        let event = ClaudeStreamEvent.parse(from: line)

        if case .result(let res) = event {
            XCTAssertEqual(res.sessionId, "abc")
            XCTAssertEqual(res.durationMs, 500)
            XCTAssertEqual(res.cost?.inputTokens, 100)
            XCTAssertEqual(res.cost?.outputTokens, 50)
        } else {
            XCTFail("Expected result event")
        }
    }

    func testUnknownEventType() {
        let line = "{\"type\":\"unknown_type\",\"data\":123}"
        let event = ClaudeStreamEvent.parse(from: line)

        if case .unknown = event {
            // Expected
        } else {
            XCTFail("Expected unknown event")
        }
    }

    func testMalformedJSON() {
        let line = "not valid json at all"
        let event = ClaudeStreamEvent.parse(from: line)

        if case .unknown = event {
            // Expected
        } else {
            XCTFail("Expected unknown event for malformed JSON")
        }
    }
}
