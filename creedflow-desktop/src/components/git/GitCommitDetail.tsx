import type { GitLogEntry } from "../../tauri";
import { X, GitCommit, User, Clock, GitBranch } from "lucide-react";

interface GitCommitDetailProps {
  commit: GitLogEntry;
  onClose: () => void;
}

export function GitCommitDetail({ commit, onClose }: GitCommitDetailProps) {
  const date = new Date(commit.timestamp * 1000);

  const branches = commit.decorations
    ? commit.decorations
        .replace(/[()]/g, "")
        .split(",")
        .map((d) => d.trim())
        .filter(Boolean)
    : [];

  return (
    <div className="w-[360px] flex-shrink-0 border-l border-zinc-800 bg-zinc-950 flex flex-col overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <div className="flex items-center gap-2 min-w-0">
          <GitCommit className="w-4 h-4 text-brand-400 flex-shrink-0" />
          <span className="text-sm font-medium text-zinc-200 truncate">
            Commit Detail
          </span>
        </div>
        <button
          onClick={onClose}
          className="p-1 rounded hover:bg-zinc-800 text-zinc-500 hover:text-zinc-300"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Hash */}
        <div>
          <label className="text-[10px] uppercase tracking-wider text-zinc-500 font-medium">
            Hash
          </label>
          <p className="mt-1 font-mono text-xs text-brand-400 select-all break-all">
            {commit.hash}
          </p>
        </div>

        {/* Message */}
        <div>
          <label className="text-[10px] uppercase tracking-wider text-zinc-500 font-medium">
            Message
          </label>
          <p className="mt-1 text-sm text-zinc-200 whitespace-pre-wrap">
            {commit.message}
          </p>
        </div>

        {/* Author */}
        <div className="flex items-center gap-2">
          <User className="w-3.5 h-3.5 text-zinc-500" />
          <span className="text-xs text-zinc-300">{commit.author}</span>
        </div>

        {/* Date */}
        <div className="flex items-center gap-2">
          <Clock className="w-3.5 h-3.5 text-zinc-500" />
          <span className="text-xs text-zinc-300">
            {date.toLocaleDateString()} {date.toLocaleTimeString()}
          </span>
        </div>

        {/* Parents */}
        {commit.parents.length > 0 && (
          <div>
            <label className="text-[10px] uppercase tracking-wider text-zinc-500 font-medium">
              Parent{commit.parents.length > 1 ? "s" : ""}
            </label>
            <div className="mt-1 space-y-1">
              {commit.parents.map((p) => (
                <p key={p} className="font-mono text-xs text-zinc-400">
                  {p.substring(0, 7)}
                </p>
              ))}
            </div>
            {commit.parents.length > 1 && (
              <span className="text-[10px] text-amber-400 mt-1 inline-block">
                Merge commit
              </span>
            )}
          </div>
        )}

        {/* Branches / Tags */}
        {branches.length > 0 && (
          <div>
            <label className="text-[10px] uppercase tracking-wider text-zinc-500 font-medium flex items-center gap-1">
              <GitBranch className="w-3 h-3" />
              Refs
            </label>
            <div className="mt-1 flex flex-wrap gap-1">
              {branches.map((b) => {
                const isHead = b.includes("HEAD");
                const isTag = b.startsWith("tag:");
                const isOrigin = b.startsWith("origin/");
                let cls = "bg-green-900/30 text-green-400";
                if (isHead) cls = "bg-brand-600/20 text-brand-400";
                else if (isTag) cls = "bg-amber-900/30 text-amber-400";
                else if (isOrigin) cls = "bg-blue-900/30 text-blue-400";
                return (
                  <span
                    key={b}
                    className={`text-[10px] px-1.5 py-0.5 rounded ${cls}`}
                  >
                    {b}
                  </span>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
