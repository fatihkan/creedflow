import type { GitLogEntry } from "../../tauri";

interface GitCommitRowProps {
  commit: GitLogEntry;
}

export function GitCommitRow({ commit }: GitCommitRowProps) {
  const date = new Date(commit.timestamp * 1000);
  const timeAgo = formatRelativeTime(date);

  // Parse decorations into branch/tag badges
  const branches = commit.decorations
    ? commit.decorations
        .replace(/[()]/g, "")
        .split(",")
        .map((d) => d.trim())
        .filter(Boolean)
    : [];

  return (
    <tr className="border-b border-zinc-800/50 hover:bg-zinc-800/30 transition-colors">
      <td className="px-4 py-2">
        <span className="font-mono text-brand-400">{commit.shortHash}</span>
      </td>
      <td className="px-4 py-2 text-zinc-300 truncate max-w-[400px]">
        {commit.message}
      </td>
      <td className="px-4 py-2">
        <div className="flex gap-1 flex-wrap">
          {branches.map((branch) => (
            <BranchTag key={branch} name={branch} />
          ))}
        </div>
      </td>
      <td className="px-4 py-2 text-zinc-500 truncate">{commit.author}</td>
      <td className="px-4 py-2 text-zinc-500" title={date.toLocaleString()}>
        {timeAgo}
      </td>
    </tr>
  );
}

function BranchTag({ name }: { name: string }) {
  const isHead = name.includes("HEAD");
  const isTag = name.startsWith("tag:");
  const isOrigin = name.startsWith("origin/");

  let bgClass = "bg-zinc-800 text-zinc-400";
  if (isHead) bgClass = "bg-brand-600/20 text-brand-400";
  else if (isTag) bgClass = "bg-amber-900/30 text-amber-400";
  else if (isOrigin) bgClass = "bg-blue-900/30 text-blue-400";
  else bgClass = "bg-green-900/30 text-green-400";

  return (
    <span className={`text-[10px] px-1.5 py-0.5 rounded ${bgClass}`}>
      {name}
    </span>
  );
}

function formatRelativeTime(date: Date): string {
  const now = Date.now();
  const diff = now - date.getTime();
  const mins = Math.floor(diff / 60000);
  const hours = Math.floor(diff / 3600000);
  const days = Math.floor(diff / 86400000);

  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  if (hours < 24) return `${hours}h ago`;
  if (days < 30) return `${days}d ago`;
  return date.toLocaleDateString();
}
