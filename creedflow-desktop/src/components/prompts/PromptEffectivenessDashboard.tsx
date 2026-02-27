import { useEffect, useState } from "react";
import { BarChart3, TrendingUp, Award } from "lucide-react";
import type { PromptEffectivenessStats } from "../../types/models";
import * as api from "../../tauri";

export function PromptEffectivenessDashboard() {
  const [stats, setStats] = useState<PromptEffectivenessStats[]>([]);
  const [loading, setLoading] = useState(true);
  const [sortBy, setSortBy] = useState<"uses" | "success" | "score">("uses");

  useEffect(() => {
    api
      .getPromptEffectiveness()
      .then(setStats)
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  const sorted = [...stats].sort((a, b) => {
    switch (sortBy) {
      case "success":
        return b.successRate - a.successRate;
      case "score":
        return (b.avgReviewScore ?? 0) - (a.avgReviewScore ?? 0);
      case "uses":
      default:
        return b.totalUses - a.totalUses;
    }
  });

  // Aggregates
  const totalUses = stats.reduce((sum, s) => sum + s.totalUses, 0);
  const totalSuccess = stats.reduce((sum, s) => sum + s.successCount, 0);
  const overallRate = totalUses > 0 ? (totalSuccess / totalUses) * 100 : 0;

  if (loading) {
    return (
      <div className="flex items-center justify-center h-32 text-zinc-500 text-sm">
        Loading effectiveness data...
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-4 space-y-4">
      {/* KPI cards */}
      <div className="grid grid-cols-3 gap-3">
        <div className="p-3 bg-zinc-900/50 rounded-lg border border-zinc-800">
          <div className="flex items-center gap-2 mb-1">
            <BarChart3 className="w-3.5 h-3.5 text-blue-400" />
            <span className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Total Uses
            </span>
          </div>
          <p className="text-xl font-bold text-zinc-100">{totalUses}</p>
        </div>
        <div className="p-3 bg-zinc-900/50 rounded-lg border border-zinc-800">
          <div className="flex items-center gap-2 mb-1">
            <TrendingUp className="w-3.5 h-3.5 text-green-400" />
            <span className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Success Rate
            </span>
          </div>
          <p className="text-xl font-bold text-zinc-100">
            {overallRate.toFixed(1)}%
          </p>
        </div>
        <div className="p-3 bg-zinc-900/50 rounded-lg border border-zinc-800">
          <div className="flex items-center gap-2 mb-1">
            <Award className="w-3.5 h-3.5 text-amber-400" />
            <span className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Tracked Prompts
            </span>
          </div>
          <p className="text-xl font-bold text-zinc-100">{stats.length}</p>
        </div>
      </div>

      {/* Sort controls */}
      <div className="flex items-center gap-2">
        <span className="text-[10px] text-zinc-500 uppercase tracking-wider">
          Sort by
        </span>
        {(["uses", "success", "score"] as const).map((s) => (
          <button
            key={s}
            onClick={() => setSortBy(s)}
            className={`px-2 py-1 text-[10px] rounded transition-colors ${
              sortBy === s
                ? "bg-brand-600/20 text-brand-400"
                : "text-zinc-500 hover:text-zinc-300 bg-zinc-800/50"
            }`}
          >
            {s === "uses" ? "Most Used" : s === "success" ? "Success Rate" : "Avg Score"}
          </button>
        ))}
      </div>

      {/* Table */}
      {sorted.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-32 text-zinc-500">
          <BarChart3 className="w-8 h-8 mb-2 opacity-40" />
          <p className="text-sm">No usage data yet</p>
          <p className="text-xs mt-1 text-zinc-600">
            Stats will appear as prompts are used in tasks
          </p>
        </div>
      ) : (
        <div className="space-y-1">
          {/* Header */}
          <div className="grid grid-cols-[1fr_60px_60px_70px_80px] gap-2 px-3 py-1.5 text-[10px] text-zinc-500 uppercase tracking-wider">
            <span>Prompt</span>
            <span className="text-right">Uses</span>
            <span className="text-right">Pass</span>
            <span className="text-right">Rate</span>
            <span className="text-right">Avg Score</span>
          </div>
          {sorted.map((s) => (
            <div
              key={s.promptId}
              className="grid grid-cols-[1fr_60px_60px_70px_80px] gap-2 items-center px-3 py-2.5 bg-zinc-900/30 rounded-md border border-zinc-800/50 hover:bg-zinc-800/30 transition-colors"
            >
              <span className="text-xs text-zinc-300 truncate">
                {s.promptTitle}
              </span>
              <span className="text-xs text-zinc-400 text-right">
                {s.totalUses}
              </span>
              <span className="text-xs text-green-400 text-right">
                {s.successCount}
              </span>
              <div className="flex items-center justify-end gap-1.5">
                <div className="w-12 h-1.5 bg-zinc-800 rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full ${
                      s.successRate >= 70
                        ? "bg-green-500"
                        : s.successRate >= 40
                          ? "bg-amber-500"
                          : "bg-red-500"
                    }`}
                    style={{ width: `${Math.min(s.successRate, 100)}%` }}
                  />
                </div>
                <span className="text-[10px] text-zinc-500 w-8 text-right">
                  {s.successRate.toFixed(0)}%
                </span>
              </div>
              <span className="text-xs text-zinc-400 text-right">
                {s.avgReviewScore != null ? s.avgReviewScore.toFixed(1) : "—"}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
