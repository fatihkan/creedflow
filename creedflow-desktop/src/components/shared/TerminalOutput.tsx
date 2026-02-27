import { useEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { Copy, Check } from "lucide-react";

interface TerminalOutputProps {
  taskId: string;
  initialContent?: string;
}

interface OutputLine {
  type: "text" | "tool_use" | "system" | "error";
  content: string;
  timestamp: number;
}

export function TerminalOutput({ taskId, initialContent }: TerminalOutputProps) {
  const [lines, setLines] = useState<OutputLine[]>(() => {
    if (initialContent) {
      return initialContent.split("\n").map((line) => ({
        type: "text" as const,
        content: line,
        timestamp: Date.now(),
      }));
    }
    return [];
  });
  const [copied, setCopied] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);

  // Listen for live task output
  useEffect(() => {
    const unlisten = listen<{
      taskId: string;
      type: string;
      content?: string;
      sessionId?: string;
      model?: string;
    }>("task-output", (event) => {
      if (event.payload.taskId !== taskId) return;

      const payload = event.payload;
      let lineType: OutputLine["type"] = "text";
      let content = payload.content || "";

      switch (payload.type) {
        case "tool_use":
          lineType = "tool_use";
          break;
        case "system":
          lineType = "system";
          content = `[session: ${payload.sessionId || "?"}, model: ${payload.model || "?"}]`;
          break;
        case "error":
          lineType = "error";
          break;
      }

      setLines((prev) => [
        ...prev,
        { type: lineType, content, timestamp: Date.now() },
      ]);
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, [taskId]);

  // Auto-scroll to bottom
  useEffect(() => {
    if (autoScroll && bottomRef.current) {
      bottomRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, [lines, autoScroll]);

  // Detect manual scroll
  const handleScroll = () => {
    if (!containerRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = containerRef.current;
    setAutoScroll(scrollHeight - scrollTop - clientHeight < 40);
  };

  const handleCopy = async () => {
    const text = lines.map((l) => l.content).join("\n");
    await navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const getLineClass = (type: OutputLine["type"]) => {
    switch (type) {
      case "error":
        return "text-red-400";
      case "system":
        return "text-blue-400";
      case "tool_use":
        return "text-amber-400";
      default:
        return "text-zinc-300";
    }
  };

  if (lines.length === 0) {
    return (
      <div className="bg-zinc-950 rounded border border-zinc-800 p-3 text-xs text-zinc-600 font-mono">
        Waiting for output...
      </div>
    );
  }

  return (
    <div className="relative bg-zinc-950 rounded border border-zinc-800 overflow-hidden">
      {/* Copy button */}
      <button
        onClick={handleCopy}
        className="absolute top-2 right-2 p-1 rounded bg-zinc-800/80 hover:bg-zinc-700 text-zinc-400 hover:text-zinc-200 transition-colors z-10"
        title="Copy all"
      >
        {copied ? (
          <Check className="w-3.5 h-3.5 text-green-400" />
        ) : (
          <Copy className="w-3.5 h-3.5" />
        )}
      </button>

      {/* Output */}
      <div
        ref={containerRef}
        onScroll={handleScroll}
        className="overflow-y-auto max-h-[400px] p-3 font-mono text-xs leading-relaxed"
      >
        {lines.map((line, i) => (
          <div key={i} className={getLineClass(line.type)}>
            {line.content || "\u00A0"}
          </div>
        ))}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}
