import { useEffect, useState } from "react";
import { gitLog, gitCurrentBranch, type GitLogEntry } from "../../tauri";
import { GitCommitRow } from "./GitCommitRow";
import { RefreshCw, GitBranch } from "lucide-react";

interface GitGraphViewProps {
  projectId: string;
}

export function GitGraphView({ projectId }: GitGraphViewProps) {
  const [commits, setCommits] = useState<GitLogEntry[]>([]);
  const [currentBranch, setCurrentBranch] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [count, setCount] = useState(50);

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
      ) : commits.length === 0 && !loading ? (
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
              {commits.map((commit) => (
                <GitCommitRow key={commit.hash} commit={commit} />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
