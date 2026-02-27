import { useEffect, useMemo, useState } from "react";
import { gitLog, gitCurrentBranch, type GitLogEntry } from "../../tauri";
import { GitCommitRow } from "./GitCommitRow";
import { RefreshCw, GitBranch, Filter } from "lucide-react";

interface GitGraphViewProps {
  projectId: string;
}

export function GitGraphView({ projectId }: GitGraphViewProps) {
  const [commits, setCommits] = useState<GitLogEntry[]>([]);
  const [currentBranch, setCurrentBranch] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [count, setCount] = useState(50);
  const [branchFilter, setBranchFilter] = useState<string>("all");

  const fetchData = async () => {
    setLoading(true);
    setError(null);
    try {
      const [log, branch] = await Promise.all([
        gitLog(projectId, count),
        gitCurrentBranch(projectId),
      ]);
      setCommits(log);
      setCurrentBranch(branch);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [projectId, count]);

  // Extract all branch names from decorations
  const branches = useMemo(() => {
    const branchSet = new Set<string>();
    commits.forEach((c) => {
      if (c.decorations) {
        // Parse decorations like "HEAD -> main, origin/main, dev"
        c.decorations.split(",").forEach((d) => {
          const trimmed = d.trim()
            .replace("HEAD -> ", "")
            .replace("tag: ", "")
            .trim();
          if (trimmed && !trimmed.startsWith("origin/")) {
            branchSet.add(trimmed);
          }
        });
      }
    });
    return Array.from(branchSet).sort();
  }, [commits]);

  // Filter commits by branch
  const filteredCommits = useMemo(() => {
    if (branchFilter === "all") return commits;
    return commits.filter((c) =>
      c.decorations.includes(branchFilter)
    );
  }, [commits, branchFilter]);

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <div className="flex items-center gap-2">
          <GitBranch className="w-4 h-4 text-zinc-400" />
          <h2 className="text-sm font-medium text-zinc-200">Git History</h2>
          {currentBranch && (
            <span className="text-xs bg-brand-600/20 text-brand-400 px-2 py-0.5 rounded">
              {currentBranch}
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          {/* Branch filter */}
          {branches.length > 0 && (
            <div className="flex items-center gap-1.5">
              <Filter className="w-3.5 h-3.5 text-zinc-500" />
              <select
                value={branchFilter}
                onChange={(e) => setBranchFilter(e.target.value)}
                className="text-xs bg-zinc-800 text-zinc-300 border border-zinc-700 rounded px-2 py-1"
              >
                <option value="all">All branches</option>
                {branches.map((b) => (
                  <option key={b} value={b}>{b}</option>
                ))}
              </select>
            </div>
          )}

          <select
            value={count}
            onChange={(e) => setCount(Number(e.target.value))}
            className="text-xs bg-zinc-800 text-zinc-300 border border-zinc-700 rounded px-2 py-1"
          >
            <option value={25}>25 commits</option>
            <option value={50}>50 commits</option>
            <option value={100}>100 commits</option>
            <option value={200}>200 commits</option>
          </select>
          <button
            onClick={fetchData}
            disabled={loading}
            className="p-1.5 rounded bg-zinc-800 hover:bg-zinc-700 text-zinc-400 hover:text-zinc-200 transition-colors disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? "animate-spin" : ""}`} />
          </button>
        </div>
      </div>

      {/* Content */}
      {error ? (
        <div className="flex-1 flex items-center justify-center text-sm text-red-400 px-4">
          {error}
        </div>
      ) : filteredCommits.length === 0 && !loading ? (
        <div className="flex-1 flex items-center justify-center text-sm text-zinc-500">
          No commits found
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto">
          <table className="w-full text-xs">
            <thead className="sticky top-0 bg-zinc-900/95 backdrop-blur">
              <tr className="border-b border-zinc-800 text-zinc-500 text-left">
                <th className="px-4 py-2 font-medium w-[72px]">Hash</th>
                <th className="px-4 py-2 font-medium">Message</th>
                <th className="px-4 py-2 font-medium w-[140px]">Branches</th>
                <th className="px-4 py-2 font-medium w-[120px]">Author</th>
                <th className="px-4 py-2 font-medium w-[140px]">Date</th>
              </tr>
            </thead>
            <tbody>
              {filteredCommits.map((commit) => (
                <GitCommitRow key={commit.hash} commit={commit} />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
