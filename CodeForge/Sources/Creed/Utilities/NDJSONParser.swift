import Foundation

/// Parses NDJSON (newline-delimited JSON) from byte chunks coming off a pipe.
///
/// Key design: a single chunk from a pipe may contain:
/// - Multiple complete JSON lines
/// - A partial JSON line at the end (needs buffering)
/// - A partial line at the start (continuation of previous buffer)
///
/// This parser handles all these cases correctly.
struct NDJSONParser: Sendable {
    private var buffer: String = ""

    /// Feed a chunk of data and extract all complete lines.
    /// Incomplete trailing data is buffered for the next call.
    mutating func feed(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return feed(text)
    }

    /// Feed a string chunk and extract all complete lines.
    mutating func feed(_ text: String) -> [String] {
        buffer += text
        var lines: [String] = []

        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }

        return lines
    }

    /// Flush any remaining buffered content as a final line.
    /// Call this when the stream ends.
    mutating func flush() -> String? {
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return remaining.isEmpty ? nil : remaining
    }
}
