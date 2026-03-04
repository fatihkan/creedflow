import { useEffect, useState } from "react";
import { useCostStore } from "../../store/costStore";
import * as api from "../../tauri";
import type { CostBreakdown } from "../../tauri";
import type { TaskStatistics } from "../../types/models";
import { DollarSign, Cpu, Server, Calendar, BarChart3, Zap } from "lucide-react";

type Tab = "overview" | "agents" | "backends" | "timeline" | "tasks" | "performance";

export function CostDashboard() {
  const { summary, fetchSummary } = useCostStore();
  const [tab, setTab] = useState<Tab>("overview");
  const [byAgent, setByAgent] = useState<CostBreakdown[]>([]);
  const [byBackend, setByBackend] = useState<CostBreakdown[]>([]);
  const [timeline, setTimeline] = useState<CostBreakdown[]>([]);
  const [taskStats, setTaskStats] = useState<TaskStatistics | null>(null);

  useEffect(() => {
    fetchSummary();
    api.getCostByAgent().then(setByAgent).catch(console.error);
    api.getCostByBackend().then(setByBackend).catch(console.error);
    api.getCostTimeline().then(setTimeline).catch(console.error);
    api.getTaskStatistics().then(setTaskStats).catch(console.error);
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
      <div className="flex border-b border-zinc-800 px-4 overflow-x-auto">
        {([
          { id: "overview" as Tab, label: "Overview", icon: DollarSign },
          { id: "agents" as Tab, label: "By Agent", icon: Cpu },
          { id: "backends" as Tab, label: "By Backend", icon: Server },
          { id: "timeline" as Tab, label: "Timeline", icon: Calendar },
          { id: "tasks" as Tab, label: "Tasks", icon: BarChart3 },
          { id: "performance" as Tab, label: "Performance", icon: Zap },
        ]).map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            className={`flex items-center gap-1.5 px-3 py-2 text-xs font-medium transition-colors whitespace-nowrap ${
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

        {tab === "tasks" && taskStats && <TasksTab stats={taskStats} />}
        {tab === "tasks" && !taskStats && (
          <p className="text-xs text-zinc-500">Loading task statistics...</p>
        )}

        {tab === "performance" && taskStats && <PerformanceTab stats={taskStats} />}
        {tab === "performance" && !taskStats && (
          <p className="text-xs text-zinc-500">Loading performance data...</p>
        )}
      </div>
    </div>
  );
}

// ─── Tasks Tab ──────────────────────────────────────────────────────────────

function TasksTab({ stats }: { stats: TaskStatistics }) {
  const avgRetries = stats.byAgent.length > 0
    ? stats.byAgent.reduce((sum, a) => sum + a.needsRevision, 0)
    : 0;

  return (
    <div className="space-y-4">
      {/* KPI cards */}
      <div className="grid grid-cols-3 gap-4">
        <KpiCard label="Total Tasks" value={String(stats.totalTasks)} />
        <KpiCard label="Success Rate" value={`${stats.successRate.toFixed(1)}%`} />
        <KpiCard label="Needs Revision" value={String(avgRetries)} />
      </div>

      {/* Bar chart: passed vs failed by agent */}
      <div>
        <h3 className="text-xs font-medium text-zinc-400 mb-3">Success vs Failure by Agent</h3>
        {stats.byAgent.length === 0 ? (
          <p className="text-xs text-zinc-500">No task data</p>
        ) : (
          <div className="space-y-2">
            {stats.byAgent.map((agent) => {
              const maxCount = Math.max(...stats.byAgent.map((a) => a.total), 1);
              return (
                <div key={agent.agentType} className="flex items-center gap-3">
                  <span className="text-xs text-zinc-400 w-28 truncate capitalize">
                    {agent.agentType}
                  </span>
                  <div className="flex-1 flex h-4 gap-0.5">
                    <div
                      className="bg-green-500/60 rounded-l"
                      style={{ width: `${(agent.passed / maxCount) * 100}%` }}
                      title={`Passed: ${agent.passed}`}
                    />
                    <div
                      className="bg-red-500/60"
                      style={{ width: `${(agent.failed / maxCount) * 100}%` }}
                      title={`Failed: ${agent.failed}`}
                    />
                    <div
                      className="bg-yellow-500/60 rounded-r"
                      style={{ width: `${(agent.needsRevision / maxCount) * 100}%` }}
                      title={`Needs Revision: ${agent.needsRevision}`}
                    />
                  </div>
                  <span className="text-[10px] text-zinc-500 w-8 text-right">
                    {agent.total}
                  </span>
                </div>
              );
            })}
            <div className="flex gap-4 mt-2">
              <span className="flex items-center gap-1 text-[10px] text-zinc-500">
                <span className="w-2 h-2 rounded-sm bg-green-500/60" /> Passed
              </span>
              <span className="flex items-center gap-1 text-[10px] text-zinc-500">
                <span className="w-2 h-2 rounded-sm bg-red-500/60" /> Failed
              </span>
              <span className="flex items-center gap-1 text-[10px] text-zinc-500">
                <span className="w-2 h-2 rounded-sm bg-yellow-500/60" /> Revision
              </span>
            </div>
          </div>
        )}
      </div>

      {/* Table */}
      <div>
        <h3 className="text-xs font-medium text-zinc-400 mb-2">By Agent Type</h3>
        {stats.byAgent.length === 0 ? (
          <p className="text-xs text-zinc-500">No data</p>
        ) : (
          <div className="space-y-1">
            <div className="grid grid-cols-[1fr_60px_60px_60px_60px_80px] gap-2 px-3 py-1 text-[10px] text-zinc-500 uppercase tracking-wider">
              <span>Agent</span>
              <span className="text-right">Total</span>
              <span className="text-right">Passed</span>
              <span className="text-right">Failed</span>
              <span className="text-right">Revision</span>
              <span className="text-right">Rate</span>
            </div>
            {stats.byAgent.map((agent) => {
              const completed = agent.passed + agent.failed;
              const rate = completed > 0 ? ((agent.passed / completed) * 100).toFixed(0) : "—";
              return (
                <div
                  key={agent.agentType}
                  className="grid grid-cols-[1fr_60px_60px_60px_60px_80px] gap-2 items-center px-3 py-2 bg-zinc-900/30 rounded border border-zinc-800/50"
                >
                  <span className="text-xs text-zinc-300 capitalize">{agent.agentType}</span>
                  <span className="text-xs text-zinc-400 text-right">{agent.total}</span>
                  <span className="text-xs text-green-400 text-right">{agent.passed}</span>
                  <span className="text-xs text-red-400 text-right">{agent.failed}</span>
                  <span className="text-xs text-yellow-400 text-right">{agent.needsRevision}</span>
                  <span className="text-xs text-zinc-300 text-right">{rate}%</span>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Performance Tab ────────────────────────────────────────────────────────

function PerformanceTab({ stats }: { stats: TaskStatistics }) {
  const formatDuration = (ms: number | null): string => {
    if (ms === null) return "—";
    if (ms < 1000) return `${Math.round(ms)}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  };

  // Find fastest agent
  const fastestAgent = stats.byAgent
    .filter((a) => a.avgDurationMs !== null)
    .sort((a, b) => (a.avgDurationMs ?? Infinity) - (b.avgDurationMs ?? Infinity))[0];

  // Velocity: tasks completed per day over last 7 days
  const last7 = stats.dailyCompleted.slice(-7);
  const velocity = last7.length > 0
    ? (last7.reduce((sum, d) => sum + d.count, 0) / 7).toFixed(1)
    : "0";

  return (
    <div className="space-y-4">
      {/* KPI cards */}
      <div className="grid grid-cols-3 gap-4">
        <KpiCard label="Avg Duration" value={formatDuration(stats.avgDurationMs)} />
        <KpiCard label="Tasks/Day (7d)" value={velocity} />
        <KpiCard
          label="Fastest Agent"
          value={fastestAgent ? fastestAgent.agentType : "—"}
        />
      </div>

      {/* Bar chart: avg duration by agent */}
      <div>
        <h3 className="text-xs font-medium text-zinc-400 mb-3">Avg Duration by Agent</h3>
        {stats.byAgent.length === 0 ? (
          <p className="text-xs text-zinc-500">No data</p>
        ) : (
          <div className="space-y-2">
            {stats.byAgent
              .filter((a) => a.avgDurationMs !== null)
              .map((agent) => {
                const maxDur = Math.max(
                  ...stats.byAgent
                    .filter((a) => a.avgDurationMs !== null)
                    .map((a) => a.avgDurationMs!),
                  1,
                );
                return (
                  <div key={agent.agentType} className="flex items-center gap-3">
                    <span className="text-xs text-zinc-400 w-28 truncate capitalize">
                      {agent.agentType}
                    </span>
                    <div className="flex-1 h-4 bg-zinc-800 rounded overflow-hidden">
                      <div
                        className="h-full bg-brand-500/60 rounded"
                        style={{
                          width: `${((agent.avgDurationMs ?? 0) / maxDur) * 100}%`,
                        }}
                      />
                    </div>
                    <span className="text-[10px] text-zinc-500 w-16 text-right">
                      {formatDuration(agent.avgDurationMs)}
                    </span>
                  </div>
                );
              })}
          </div>
        )}
      </div>

      {/* Daily velocity chart */}
      <div>
        <h3 className="text-xs font-medium text-zinc-400 mb-3">Tasks Completed (Last 30 Days)</h3>
        {stats.dailyCompleted.length === 0 ? (
          <p className="text-xs text-zinc-500">No completions in the last 30 days</p>
        ) : (
          <div className="space-y-1">
            <div className="flex items-end gap-1 h-32">
              {stats.dailyCompleted.map((day) => {
                const maxCount = Math.max(...stats.dailyCompleted.map((d) => d.count), 1);
                const height = (day.count / maxCount) * 100;
                return (
                  <div
                    key={day.date}
                    className="flex-1 group relative"
                    title={`${day.date}: ${day.count} tasks`}
                  >
                    <div
                      className="bg-green-500/60 hover:bg-green-400/70 rounded-t transition-colors w-full"
                      style={{ height: `${Math.max(height, 4)}%` }}
                    />
                  </div>
                );
              })}
            </div>
            <div className="mt-4 space-y-1">
              <div className="grid grid-cols-[1fr_80px] gap-2 px-3 py-1 text-[10px] text-zinc-500 uppercase tracking-wider">
                <span>Date</span>
                <span className="text-right">Completed</span>
              </div>
              {[...stats.dailyCompleted].reverse().map((day) => (
                <div
                  key={day.date}
                  className="grid grid-cols-[1fr_80px] gap-2 items-center px-3 py-2 bg-zinc-900/30 rounded border border-zinc-800/50"
                >
                  <span className="text-xs text-zinc-300">{day.date}</span>
                  <span className="text-xs text-zinc-400 text-right">{day.count}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Shared Components ──────────────────────────────────────────────────────

function KpiCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="p-4 bg-zinc-900/50 rounded-lg border border-zinc-800">
      <p className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">{label}</p>
      <p className="text-2xl font-bold text-zinc-100 mt-1 capitalize">{value}</p>
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
