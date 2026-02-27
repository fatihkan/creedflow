import { useEffect, useState } from "react";
import { useCostStore } from "../../store/costStore";
import * as api from "../../tauri";
import type { CostBreakdown } from "../../tauri";
import { DollarSign, Cpu, Server, Calendar } from "lucide-react";

type Tab = "overview" | "agents" | "backends" | "timeline";

export function CostDashboard() {
  const { summary, fetchSummary } = useCostStore();
  const [tab, setTab] = useState<Tab>("overview");
  const [byAgent, setByAgent] = useState<CostBreakdown[]>([]);
  const [byBackend, setByBackend] = useState<CostBreakdown[]>([]);
  const [timeline, setTimeline] = useState<CostBreakdown[]>([]);

  useEffect(() => {
    fetchSummary();
    api.getCostByAgent().then(setByAgent).catch(console.error);
    api.getCostByBackend().then(setByBackend).catch(console.error);
    api.getCostTimeline().then(setTimeline).catch(console.error);
  }, [fetchSummary]);

  return (
    <div className="flex-1 flex flex-col">
      <div className="px-4 py-3 border-b border-zinc-800">
        <h2 className="text-sm font-semibold text-zinc-200">Cost Dashboard</h2>
      </div>

      {/* KPI cards */}
      <div className="p-4">
        <div className="grid grid-cols-3 gap-4">
          <KpiCard label="Total Cost" value={`$${summary?.totalCost.toFixed(2) ?? "0.00"}`} />
          <KpiCard label="Tasks Tracked" value={String(summary?.totalTasks ?? 0)} />
          <KpiCard label="Total Tokens" value={summary?.totalTokens?.toLocaleString() ?? "0"} />
        </div>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-zinc-800 px-4">
        {([
          { id: "overview" as Tab, label: "Overview", icon: DollarSign },
          { id: "agents" as Tab, label: "By Agent", icon: Cpu },
          { id: "backends" as Tab, label: "By Backend", icon: Server },
          { id: "timeline" as Tab, label: "Timeline", icon: Calendar },
        ]).map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            className={`flex items-center gap-1.5 px-3 py-2 text-xs font-medium transition-colors ${
              tab === id
                ? "text-brand-400 border-b-2 border-brand-400"
                : "text-zinc-500 hover:text-zinc-300"
            }`}
          >
            <Icon className="w-3 h-3" />
            {label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div className="flex-1 overflow-y-auto p-4">
        {tab === "overview" && (
          <div className="grid grid-cols-2 gap-4">
            <BreakdownTable title="Top Agents" data={byAgent.slice(0, 5)} />
            <BreakdownTable title="Top Backends" data={byBackend.slice(0, 5)} />
          </div>
        )}

        {tab === "agents" && <BreakdownTable title="Cost by Agent" data={byAgent} />}
        {tab === "backends" && <BreakdownTable title="Cost by Backend" data={byBackend} />}

        {tab === "timeline" && (
          <div className="space-y-3">
            <h3 className="text-xs font-medium text-zinc-400">Last 30 Days</h3>
            {timeline.length === 0 ? (
              <p className="text-xs text-zinc-500">No cost data in the last 30 days</p>
            ) : (
              <div className="space-y-1">
                {/* Bar chart */}
                <div className="flex items-end gap-1 h-32">
                  {timeline.map((day) => {
                    const maxCost = Math.max(...timeline.map((d) => d.cost), 0.01);
                    const height = (day.cost / maxCost) * 100;
                    return (
                      <div
                        key={day.label}
                        className="flex-1 group relative"
                        title={`${day.label}: $${day.cost.toFixed(2)}`}
                      >
                        <div
                          className="bg-brand-500/60 hover:bg-brand-400/70 rounded-t transition-colors w-full"
                          style={{ height: `${Math.max(height, 2)}%` }}
                        />
                      </div>
                    );
                  })}
                </div>
                {/* Table below */}
                <div className="mt-4 space-y-1">
                  <div className="grid grid-cols-[1fr_80px_60px_80px] gap-2 px-3 py-1 text-[10px] text-zinc-500 uppercase tracking-wider">
                    <span>Date</span>
                    <span className="text-right">Cost</span>
                    <span className="text-right">Tasks</span>
                    <span className="text-right">Tokens</span>
                  </div>
                  {[...timeline].reverse().map((day) => (
                    <div
                      key={day.label}
                      className="grid grid-cols-[1fr_80px_60px_80px] gap-2 items-center px-3 py-2 bg-zinc-900/30 rounded border border-zinc-800/50"
                    >
                      <span className="text-xs text-zinc-300">{day.label}</span>
                      <span className="text-xs text-zinc-400 text-right">${day.cost.toFixed(4)}</span>
                      <span className="text-xs text-zinc-500 text-right">{day.tasks}</span>
                      <span className="text-xs text-zinc-500 text-right">{day.tokens.toLocaleString()}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function KpiCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="p-4 bg-zinc-900/50 rounded-lg border border-zinc-800">
      <p className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">{label}</p>
      <p className="text-2xl font-bold text-zinc-100 mt-1">{value}</p>
    </div>
  );
}

function BreakdownTable({ title, data }: { title: string; data: CostBreakdown[] }) {
  const maxCost = Math.max(...data.map((d) => d.cost), 0.01);

  return (
    <div>
      <h3 className="text-xs font-medium text-zinc-400 mb-2">{title}</h3>
      {data.length === 0 ? (
        <p className="text-xs text-zinc-500">No data</p>
      ) : (
        <div className="space-y-1">
          <div className="grid grid-cols-[1fr_80px_60px_80px] gap-2 px-3 py-1 text-[10px] text-zinc-500 uppercase tracking-wider">
            <span>Name</span>
            <span className="text-right">Cost</span>
            <span className="text-right">Tasks</span>
            <span className="text-right">Tokens</span>
          </div>
          {data.map((row) => (
            <div
              key={row.label}
              className="grid grid-cols-[1fr_80px_60px_80px] gap-2 items-center px-3 py-2 bg-zinc-900/30 rounded border border-zinc-800/50"
            >
              <div className="flex items-center gap-2">
                <div className="w-16 h-1.5 bg-zinc-800 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-brand-500/60 rounded-full"
                    style={{ width: `${(row.cost / maxCost) * 100}%` }}
                  />
                </div>
                <span className="text-xs text-zinc-300 capitalize">{row.label}</span>
              </div>
              <span className="text-xs text-zinc-400 text-right">${row.cost.toFixed(4)}</span>
              <span className="text-xs text-zinc-500 text-right">{row.tasks}</span>
              <span className="text-xs text-zinc-500 text-right">{row.tokens.toLocaleString()}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
