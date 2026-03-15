import { useEffect, useRef, useState } from "react";
import * as api from "../../tauri";

interface DiagramInfo {
  name: string;
  path: string;
}

/**
 * Renders a single Mermaid diagram using a sandboxed iframe.
 */
function MermaidRenderer({ code }: { code: string }) {
  const iframeRef = useRef<HTMLIFrameElement>(null);

  useEffect(() => {
    if (!iframeRef.current) return;

    const escaped = code.replace(/\\/g, "\\\\").replace(/`/g, "\\`").replace(/\$/g, "\\$");

    const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { margin: 0; padding: 16px; background: #09090b; display: flex; justify-content: center; }
    .error { color: #ff6b6b; font-size: 12px; padding: 8px; font-family: monospace; }
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
      const { svg } = await mermaid.render('diagram', \`${escaped}\`);
      document.getElementById('output').innerHTML = svg;
      // Resize iframe to content
      const height = document.body.scrollHeight;
      window.parent.postMessage({ type: 'mermaid-height', height }, '*');
    } catch (e) {
      document.getElementById('output').innerHTML = '<div class="error">Render error: ' + e.message + '</div>';
      window.parent.postMessage({ type: 'mermaid-height', height: 60 }, '*');
    }
  </script>
</head>
<body><div id="output"></div></body>
</html>`;

    iframeRef.current.srcdoc = html;
  }, [code]);

  const [height, setHeight] = useState(300);

  useEffect(() => {
    const handler = (e: MessageEvent) => {
      if (e.data?.type === "mermaid-height" && typeof e.data.height === "number") {
        setHeight(Math.max(100, Math.min(e.data.height + 32, 600)));
      }
    };
    window.addEventListener("message", handler);
    return () => window.removeEventListener("message", handler);
  }, []);

  return (
    <iframe
      ref={iframeRef}
      sandbox="allow-scripts"
      className="w-full border border-zinc-800 rounded-md bg-zinc-950"
      style={{ height, border: "none" }}
      title="Mermaid Diagram"
    />
  );
}

/**
 * Lists and displays Mermaid diagrams from a project's docs/diagrams/ directory.
 */
export function ProjectDiagramsPanel({ projectId }: { projectId: string }) {
  const [diagrams, setDiagrams] = useState<DiagramInfo[]>([]);
  const [selectedIdx, setSelectedIdx] = useState(0);
  const [content, setContent] = useState<string | null>(null);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    api.listProjectDiagrams(projectId).then((d) => {
      setDiagrams(d);
      setSelectedIdx(0);
    }).catch(() => setDiagrams([]));
  }, [projectId]);

  useEffect(() => {
    if (diagrams.length > 0 && selectedIdx < diagrams.length) {
      api.getDiagramContent(diagrams[selectedIdx].path)
        .then(setContent)
        .catch(() => setContent(null));
    } else {
      setContent(null);
    }
  }, [diagrams, selectedIdx]);

  if (diagrams.length === 0) return null;

  return (
    <div className="space-y-2">
      <button
        onClick={() => setExpanded(!expanded)}
        className="flex items-center gap-1.5 text-[10px] font-medium text-zinc-500 uppercase tracking-wider hover:text-zinc-300 transition-colors"
      >
        <span className={`transition-transform ${expanded ? "rotate-90" : ""}`}>&#9654;</span>
        Diagrams ({diagrams.length})
      </button>

      {expanded && (
        <div className="space-y-2">
          {diagrams.length > 1 && (
            <div className="flex gap-1 flex-wrap">
              {diagrams.map((d, i) => (
                <button
                  key={d.path}
                  onClick={() => setSelectedIdx(i)}
                  className={`text-[10px] px-2 py-1 rounded transition-colors ${
                    i === selectedIdx
                      ? "bg-amber-500/15 text-amber-400 font-medium"
                      : "bg-zinc-800 text-zinc-400 hover:text-zinc-300"
                  }`}
                >
                  {d.name}
                </button>
              ))}
            </div>
          )}

          {content && <MermaidRenderer code={content} />}
        </div>
      )}
    </div>
  );
}
