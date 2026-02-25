import { useEffect } from "react";
import { useCostStore } from "../../store/costStore";

export function CostDashboard() {
  const { summary, fetchSummary } = useCostStore();

  useEffect(() => {
    fetchSummary();
  }, [fetchSummary]);

  return (
    <div className="flex-1 flex flex-col">
      <div className="px-4 py-3 border-b border-zinc-800">
        <h2 className="text-sm font-semibold text-zinc-200">Cost Dashboard</h2>
      </div>

      <div className="p-4">
        <div className="grid grid-cols-3 gap-4">
          <div className="p-4 bg-zinc-900/50 rounded-lg border border-zinc-800">
            <p className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Total Cost
            </p>
            <p className="text-2xl font-bold text-zinc-100 mt-1">
              ${summary?.totalCost.toFixed(2) ?? "0.00"}
            </p>
          </div>
          <div className="p-4 bg-zinc-900/50 rounded-lg border border-zinc-800">
            <p className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Tasks Tracked
            </p>
            <p className="text-2xl font-bold text-zinc-100 mt-1">
              {summary?.totalTasks ?? 0}
            </p>
          </div>
          <div className="p-4 bg-zinc-900/50 rounded-lg border border-zinc-800">
            <p className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Total Tokens
            </p>
            <p className="text-2xl font-bold text-zinc-100 mt-1">
              {summary?.totalTokens?.toLocaleString() ?? 0}
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
