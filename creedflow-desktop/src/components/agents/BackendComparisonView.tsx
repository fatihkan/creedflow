import { useEffect, useState } from "react";
import { Play, Loader2, Clock, AlertCircle } from "lucide-react";
import * as api from "../../tauri";
import type { BackendInfo } from "../../types/models";
import type { ComparisonResult } from "../../tauri";

export function BackendComparisonView() {
  const [backends, setBackends] = useState<BackendInfo[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [prompt, setPrompt] = useState("");
  const [results, setResults] = useState<ComparisonResult[]>([]);
  const [running, setRunning] = useState(false);

  useEffect(() => {
    api.listBackends().then((list) => {
      setBackends(list.filter((b) => b.isEnabled && b.isAvailable));
      const enabled = list.filter((b) => b.isEnabled && b.isAvailable).map((b) => b.backendType);
      setSelected(new Set(enabled.slice(0, 3)));
    }).catch(console.error);
  }, []);

  const toggleBackend = (type: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(type)) next.delete(type);
      else next.add(type);
      return next;
    });
  };

  const runComparison = async () => {
    if (!prompt.trim() || selected.size < 2) return;
    setRunning(true);
    setResults([]);
    try {
      const res = await api.compareBackends(prompt, Array.from(selected));
      setResults(res);
    } catch (e) {
      console.error(e);
    } finally {
      setRunning(false);
    }
  };

  const BADGE_COLORS: Record<string, string> = {
    claude: "bg-purple-500/20 text-purple-400",
    codex: "bg-green-500/20 text-green-400",
    gemini: "bg-blue-500/20 text-blue-400",
    ollama: "bg-orange-500/20 text-orange-400",
    lmstudio: "bg-cyan-500/20 text-cyan-400",
    llamacpp: "bg-pink-500/20 text-pink-400",
    mlx: "bg-emerald-500/20 text-emerald-400",
    opencode: "bg-indigo-500/20 text-indigo-400",
    openclaw: "bg-amber-500/20 text-amber-400",
  };

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="px-4 py-3 border-b border-zinc-800">
        <h2 className="text-sm font-semibold text-zinc-200">Compare Backends</h2>
        <p className="text-[10px] text-zinc-500 mt-0.5">
          Run the same prompt across multiple AI backends side-by-side
        </p>
      </div>

      <div className="p-4 space-y-4 border-b border-zinc-800">
        {/* Prompt */}
        <div>
          <label className="block text-xs text-zinc-400 mb-1">Prompt</label>
          <textarea
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            placeholder="Enter a prompt to compare across backends..."
            rows={3}
            className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600 resize-none"
          />
        </div>

        {/* Backend selection */}
        <div>
          <label className="block text-xs text-zinc-400 mb-2">Backends (select 2+)</label>
          <div className="flex flex-wrap gap-2">
            {backends.map((b) => (
              <button
                key={b.backendType}
                onClick={() => toggleBackend(b.backendType)}
                className={`px-3 py-1.5 text-xs rounded border transition-colors ${
                  selected.has(b.backendType)
                    ? "bg-brand-600/20 border-brand-500 text-brand-400"
                    : "bg-zinc-800 border-zinc-700 text-zinc-400 hover:text-zinc-200"
                }`}
              >
                {b.backendType}
              </button>
            ))}
          </div>
        </div>

        {/* Run button */}
        <button
          onClick={runComparison}
          disabled={running || !prompt.trim() || selected.size < 2}
          className="flex items-center gap-2 px-4 py-2 text-xs bg-brand-600 text-white rounded hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {running ? (
            <>
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
              Running...
            </>
          ) : (
            <>
              <Play className="w-3.5 h-3.5" />
              Run Comparison
            </>
          )}
        </button>
      </div>

      {/* Results */}
      <div className="flex-1 overflow-x-auto overflow-y-auto p-4">
        {results.length > 0 && (
          <div className="flex gap-4 min-w-max">
            {results.map((r) => (
              <div
                key={r.backendType}
                className="w-[400px] flex-shrink-0 bg-zinc-800/30 border border-zinc-700/50 rounded-lg overflow-hidden"
              >
                {/* Card header */}
                <div className="flex items-center justify-between px-4 py-2.5 border-b border-zinc-700/50">
                  <span className={`text-xs font-medium px-2 py-0.5 rounded ${BADGE_COLORS[r.backendType] || "bg-zinc-700 text-zinc-300"}`}>
                    {r.backendType}
                  </span>
                  <div className="flex items-center gap-2 text-[10px] text-zinc-500">
                    {r.error ? (
                      <span className="flex items-center gap-1 text-red-400">
                        <AlertCircle className="w-3 h-3" /> Error
                      </span>
                    ) : (
                      <span className="flex items-center gap-1">
                        <Clock className="w-3 h-3" />
                        {(r.durationMs / 1000).toFixed(1)}s
                      </span>
                    )}
                  </div>
                </div>

                {/* Card body */}
                <div className="p-4 max-h-[500px] overflow-y-auto">
                  {r.error ? (
                    <p className="text-xs text-red-400">{r.error}</p>
                  ) : (
                    <pre className="text-xs text-zinc-300 whitespace-pre-wrap font-mono leading-relaxed">
                      {r.output}
                    </pre>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {results.length === 0 && !running && (
          <div className="flex-1 flex items-center justify-center text-zinc-600 text-xs h-full">
            Enter a prompt and select backends to compare
          </div>
        )}
      </div>
    </div>
  );
}
