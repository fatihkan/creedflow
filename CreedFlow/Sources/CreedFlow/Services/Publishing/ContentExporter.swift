import Foundation
import AppKit
import WebKit

/// Exports content from Markdown to multiple formats (HTML, plaintext, PDF).
struct ContentExporter: Sendable {

    /// Export the content of a text-based asset to the given format.
    func export(filePath: String, title: String, format: Publication.ExportFormat) async throws -> ExportedContent {
        let markdown = try String(contentsOfFile: filePath, encoding: .utf8)

        switch format {
        case .markdown:
            return ExportedContent(title: title, body: markdown, format: .markdown)
        case .html:
            let html = markdownToHTML(markdown, title: title)
            return ExportedContent(title: title, body: html, format: .html)
        case .plaintext:
            let plain = stripMarkdown(markdown)
            return ExportedContent(title: title, body: plain, format: .plaintext)
        case .pdf:
            let html = markdownToHTML(markdown, title: title)
            return ExportedContent(title: title, body: html, format: .pdf)
        }
    }

    // MARK: - Private

    /// Convert Markdown to HTML using AttributedString (macOS 12+).
    private func markdownToHTML(_ markdown: String, title: String) -> String {
        // Use a simple regex-based conversion for common Markdown patterns
        var html = markdown

        // Headers
        html = html.replacingOccurrences(of: "(?m)^### (.+)$", with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^## (.+)$", with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^# (.+)$", with: "<h1>$1</h1>", options: .regularExpression)

        // Bold and italic
        html = html.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)

        // Code blocks
        html = html.replacingOccurrences(of: "```([\\s\\S]*?)```", with: "<pre><code>$1</code></pre>", options: .regularExpression)
        html = html.replacingOccurrences(of: "`(.+?)`", with: "<code>$1</code>", options: .regularExpression)

        // Links
        html = html.replacingOccurrences(of: "\\[(.+?)\\]\\((.+?)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)

        // Paragraphs (double newlines)
        html = html.replacingOccurrences(of: "\n\n", with: "</p><p>")

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(title)</title>
        <style>body{font-family:-apple-system,sans-serif;max-width:700px;margin:2em auto;line-height:1.6;color:#333;}
        pre{background:#f5f5f5;padding:1em;overflow-x:auto;}code{background:#f5f5f5;padding:0.2em 0.4em;}</style>
        </head><body><p>\(html)</p></body></html>
        """
    }

    /// Strip Markdown syntax to produce plaintext.
    private func stripMarkdown(_ markdown: String) -> String {
        var text = markdown

        // Remove headers
        text = text.replacingOccurrences(of: "(?m)^#{1,6} ", with: "", options: .regularExpression)
        // Remove bold/italic markers
        text = text.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
        // Remove links, keep text
        text = text.replacingOccurrences(of: "\\[(.+?)\\]\\(.+?\\)", with: "$1", options: .regularExpression)
        // Remove code fences
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "`(.+?)`", with: "$1", options: .regularExpression)
        // Remove images
        text = text.replacingOccurrences(of: "!\\[.*?\\]\\(.*?\\)", with: "", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
