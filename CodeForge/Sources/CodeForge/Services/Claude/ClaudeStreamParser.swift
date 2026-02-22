import Foundation

/// High-level parser that converts raw pipe bytes into `ClaudeStreamEvent`s
/// using `NDJSONParser` for line extraction.
struct ClaudeStreamParser: Sendable {
    private var ndjsonParser = NDJSONParser()

    /// Feed a data chunk and return all parsed events
    mutating func feed(_ data: Data) -> [ClaudeStreamEvent] {
        ndjsonParser.feed(data).compactMap(ClaudeStreamEvent.parse)
    }

    /// Flush remaining buffer and return any final event
    mutating func flush() -> ClaudeStreamEvent? {
        guard let line = ndjsonParser.flush() else { return nil }
        return ClaudeStreamEvent.parse(from: line)
    }
}
