import { useEffect, useMemo, useState } from "react";
import { gitLog, gitCurrentBranch, type GitLogEntry } from "../../tauri";
import { GitCommitRow, type LaneData } from "./GitCommitRow";
import { GitCommitDetail } from "./GitCommitDetail";
import { SearchBar } from "../shared/SearchBar";
import { RefreshCw, GitBranch, Filter } from "lucide-react";

const LANE_COLORS = [
  "#6366f1", "#22c55e", "#3b82f6", "#f59e0b",
  "#ef4444", "#a855f7", "#06b6d4", "#ec4899",
];

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
  const [search, setSearch] = useState("");
  const [selectedCommit, setSelectedCommit] = useState<GitLogEntry | null>(null);

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
  const branchFiltered = useMemo(() => {
    if (branchFilter === "all") return commits;
    return commits.filter((c) =>
      c.decorations.includes(branchFilter)
    );
  }, [commits, branchFilter]);

  // Filter by search query
  const filteredCommits = useMemo(() => {
    if (!search.trim()) return branchFiltered;
    const q = search.toLowerCase();
    return branchFiltered.filter(
      (c) =>
        c.message.toLowerCase().includes(q) ||
        c.hash.toLowerCase().includes(q) ||
        c.shortHash.toLowerCase().includes(q) ||
        c.author.toLowerCase().includes(q),
    );
  }, [branchFiltered, search]);

  // Compute graph lane data
  const laneMap = useMemo(() => {
    const map = new Map<string, LaneData>();
    // Track active lanes: each lane holds the hash of the commit it's waiting for
    const activeLanes: (string | null)[] = [];

    const findLane = (hash: string): number => {
      for (let i = 0; i < activeLanes.length; i++) {
        if (activeLanes[i] === hash) return i;
      }
      return -1;
    };

    const nextFreeLane = (): number => {
      for (let i = 0; i < activeLanes.length; i++) {
        if (activeLanes[i] === null) return i;
      }
      activeLanes.push(null);
      return activeLanes.length - 1;
    };

    for (const commit of commits) {
      let lane = findLane(commit.hash);
      if (lane === -1) {
        lane = nextFreeLane();
      }

      const connections: LaneData["connections"] = [];

      // Draw continuation lines for all other active lanes
      for (let i = 0; i < activeLanes.length; i++) {
        if (activeLanes[i] !== null && i !== lane) {
          connections.push({ from: i, to: i, type: "continue" });
        }
      }

      const parents = commit.parents;

      if (parents.length === 0) {
        // Root commit — close lane
        activeLanes[lane] = null;
      } else if (parents.length === 1) {
        // Linear commit — assign parent to same lane
        activeLanes[lane] = parents[0];
      } else {
        // Merge commit — first parent stays in lane, others get merge lines
        activeLanes[lane] = parents[0];
        for (let p = 1; p < parents.length; p++) {
          const parentLane = findLane(parents[p]);
          if (parentLane !== -1) {
            connections.push({ from: parentLane, to: lane, type: "merge" });
          } else {
            // Parent not in any lane — assign to new lane and draw merge
            const newLane = nextFreeLane();
            activeLanes[newLane] = parents[p];
            connections.push({ from: newLane, to: lane, type: "merge" });
          }
        }
      }

      map.set(commit.hash, {
        lane,
        totalLanes: activeLanes.length,
        connections,
        color: LANE_COLORS[lane % LANE_COLORS.length],
      });
    }

    return map;
  }, [commits]);

  return (
    <div className="flex-1 flex overflow-hidden">
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
            <SearchBar
              value={search}
              onChange={setSearch}
              placeholder="Search commits..."
            />

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
              aria-label="Refresh git history"
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
            {search ? "No commits matching search" : "No commits found"}
          </div>
        ) : (
          <div className="flex-1 overflow-y-auto">
            <table className="w-full text-xs">
              <thead className="sticky top-0 bg-zinc-900/95 backdrop-blur">
                <tr className="border-b border-zinc-800 text-zinc-500 text-left">
                  <th className="px-0 py-2 font-medium w-[60px]"></th>
                  <th className="px-4 py-2 font-medium w-[72px]">Hash</th>
                  <th className="px-4 py-2 font-medium">Message</th>
                  <th className="px-4 py-2 font-medium w-[140px]">Branches</th>
                  <th className="px-4 py-2 font-medium w-[120px]">Author</th>
                  <th className="px-4 py-2 font-medium w-[140px]">Date</th>
                </tr>
              </thead>
              <tbody>
                {filteredCommits.map((commit) => (
                  <GitCommitRow
                    key={commit.hash}
                    commit={commit}
                    laneData={laneMap.get(commit.hash)}
                    onClick={() => setSelectedCommit(commit)}
                    isSelected={selectedCommit?.hash === commit.hash}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Commit detail panel */}
      {selectedCommit && (
        <GitCommitDetail
          commit={selectedCommit}
          onClose={() => setSelectedCommit(null)}
        />
      )}
    </div>
  );
}
