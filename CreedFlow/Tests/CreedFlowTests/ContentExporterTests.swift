import Foundation
@testable import CreedFlowLib

enum ContentExporterTests {
    static func runAll() {
        testExportMarkdownFormat()
        testExportHTMLFormat()
        testExportPlaintextFormat()
        testExportPDFFormatReturnsHTML()
        testHTMLContainsHeaders()
        testHTMLContainsBoldAndItalic()
        testHTMLContainsLinks()
        testHTMLContainsCodeBlocks()
        testPlaintextStripsHeaders()
        testPlaintextStripsFormatting()
        testPlaintextStripsLinks()
        print("  ContentExporterTests: 11/11 passed")
    }

    // MARK: - Helpers

    private static func runBlocking<T>(_ block: @Sendable @escaping () async throws -> T) throws -> T {
        var result: Result<T, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let value = try await block()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result!.get()
    }

    private static func writeTempMarkdown(_ content: String) -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("creedflow-test-\(UUID().uuidString).md").path
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    // MARK: - Format Tests

    static func testExportMarkdownFormat() {
        let md = "# Hello World\n\nThis is **bold** text."
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "Test", format: .markdown) }

        assertEq(result.format, .markdown)
        assertEq(result.title, "Test")
        assertEq(result.body, md)
    }

    static func testExportHTMLFormat() {
        let md = "# Title\n\nSome text."
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "Doc", format: .html) }

        assertEq(result.format, .html)
        assertTrue(result.body.contains("<!DOCTYPE html>"))
        assertTrue(result.body.contains("<h1>Title</h1>"))
        assertTrue(result.body.contains("Some text."))
    }

    static func testExportPlaintextFormat() {
        let md = "# Title\n\nSome **bold** text."
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "Doc", format: .plaintext) }

        assertEq(result.format, .plaintext)
        assertTrue(!result.body.contains("#"))
        assertTrue(!result.body.contains("**"))
        assertTrue(result.body.contains("bold"))
    }

    static func testExportPDFFormatReturnsHTML() {
        let md = "# PDF Test\n\nContent here."
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "PDF", format: .pdf) }

        assertEq(result.format, .pdf)
        // PDF format returns HTML for caller to convert
        assertTrue(result.body.contains("<!DOCTYPE html>"))
    }

    // MARK: - HTML Conversion Detail Tests

    static func testHTMLContainsHeaders() {
        let md = "# H1 Title\n\n## H2 Subtitle\n\n### H3 Section"
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "Headers", format: .html) }

        assertTrue(result.body.contains("<h1>H1 Title</h1>"))
        assertTrue(result.body.contains("<h2>H2 Subtitle</h2>"))
        assertTrue(result.body.contains("<h3>H3 Section</h3>"))
    }

    static func testHTMLContainsBoldAndItalic() {
        let md = "This is **bold** and *italic* text."
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "Format", format: .html) }

        assertTrue(result.body.contains("<strong>bold</strong>"))
        assertTrue(result.body.contains("<em>italic</em>"))
    }

    static func testHTMLContainsLinks() {
        let md = "Visit [Google](https://google.com) for search."
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "Links", format: .html) }

        assertTrue(result.body.contains("<a href=\"https://google.com\">Google</a>"))
    }

    static func testHTMLContainsCodeBlocks() {
        let md = "Use `inline code` and:\n\n```\nlet x = 1\n```"
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "Code", format: .html) }

        assertTrue(result.body.contains("<code>"))
    }

    // MARK: - Plaintext Stripping Tests

    static func testPlaintextStripsHeaders() {
        let md = "# Title\n## Subtitle\n### Section"
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "Strip", format: .plaintext) }

        assertTrue(!result.body.contains("# "))
        assertTrue(result.body.contains("Title"))
        assertTrue(result.body.contains("Subtitle"))
    }

    static func testPlaintextStripsFormatting() {
        let md = "This is **bold** and *italic*."
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "Strip", format: .plaintext) }

        assertTrue(!result.body.contains("**"))
        assertTrue(!result.body.contains("*"))
        assertTrue(result.body.contains("bold"))
        assertTrue(result.body.contains("italic"))
    }

    static func testPlaintextStripsLinks() {
        let md = "Visit [Google](https://google.com) now."
        let path = writeTempMarkdown(md)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let exporter = ContentExporter()
        let result = try! runBlocking { try await exporter.export(filePath: path, title: "Strip", format: .plaintext) }

        assertTrue(!result.body.contains("["))
        assertTrue(!result.body.contains("]("))
        assertTrue(result.body.contains("Google"))
    }
}
