import SwiftUI
import WebKit

/// Renders a Mermaid diagram string using WKWebView with a bundled Mermaid.js CDN.
struct MermaidDiagramView: NSViewRepresentable {
    let mermaidCode: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadMermaid(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadMermaid(webView: webView)
    }

    private func loadMermaid(webView: WKWebView) {
        let escaped = mermaidCode
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                body {
                    margin: 0; padding: 16px;
                    background: transparent;
                    display: flex; justify-content: center;
                    font-family: -apple-system, system-ui, sans-serif;
                }
                .mermaid { max-width: 100%; }
                .error { color: #ff6b6b; font-size: 12px; padding: 8px; }
            </style>
            <script type="module">
                import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
                mermaid.initialize({
                    startOnLoad: false,
                    theme: 'dark',
                    themeVariables: {
                        primaryColor: '#d4a017',
                        primaryTextColor: '#e4e4e7',
                        primaryBorderColor: '#52525b',
                        lineColor: '#71717a',
                        secondaryColor: '#27272a',
                        tertiaryColor: '#18181b',
                        background: '#09090b',
                        mainBkg: '#27272a',
                        nodeBorder: '#52525b',
                        clusterBkg: '#18181b',
                        titleColor: '#e4e4e7',
                        edgeLabelBackground: '#18181b'
                    }
                });
                try {
                    const { svg } = await mermaid.render('diagram', `\(escaped)`);
                    document.getElementById('output').innerHTML = svg;
                } catch (e) {
                    document.getElementById('output').innerHTML = '<div class="error">Failed to render: ' + e.message + '</div>';
                }
            </script>
        </head>
        <body><div id="output" class="mermaid"></div></body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

/// Lists and displays Mermaid diagrams from a project's docs/diagrams/ directory.
struct ProjectDiagramsView: View {
    let projectDirectoryPath: String

    @State private var diagrams: [(name: String, content: String)] = []
    @State private var selectedIndex: Int?

    var body: some View {
        if diagrams.isEmpty {
            Text("No diagrams available")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        } else {
            DisclosureGroup("Diagrams (\(diagrams.count))") {
                VStack(alignment: .leading, spacing: 6) {
                    // Diagram selector
                    if diagrams.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(diagrams.enumerated()), id: \.offset) { idx, diagram in
                                    Button {
                                        selectedIndex = idx
                                    } label: {
                                        Text(diagram.name)
                                            .font(.system(size: 11, weight: selectedIndex == idx ? .semibold : .regular))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(selectedIndex == idx ? Color.orange.opacity(0.15) : Color.gray.opacity(0.15))
                                            .foregroundStyle(selectedIndex == idx ? Color.orange : .secondary)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Render selected diagram
                    if let idx = selectedIndex, idx < diagrams.count {
                        MermaidDiagramView(mermaidCode: diagrams[idx].content)
                            .frame(minHeight: 250, maxHeight: 500)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.quaternary, lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 4)
            }
            .font(.subheadline.bold())
        }
    }

    func loadDiagrams() -> some View {
        self.task {
            let diagramsDir = URL(fileURLWithPath: projectDirectoryPath)
                .appendingPathComponent("docs")
                .appendingPathComponent("diagrams")
            let fm = FileManager.default
            guard fm.fileExists(atPath: diagramsDir.path) else { return }

            do {
                let contents = try fm.contentsOfDirectory(at: diagramsDir, includingPropertiesForKeys: nil)
                let mmdFiles = contents.filter { $0.pathExtension == "mmd" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

                var loaded: [(name: String, content: String)] = []
                for file in mmdFiles {
                    if let content = try? String(contentsOf: file, encoding: .utf8) {
                        let name = file.deletingPathExtension().lastPathComponent
                            .replacingOccurrences(of: "-", with: " ")
                            .replacingOccurrences(of: "_", with: " ")
                        loaded.append((name: name, content: content))
                    }
                }
                diagrams = loaded
                if !loaded.isEmpty { selectedIndex = 0 }
            } catch {
                // silently fail
            }
        }
    }
}
