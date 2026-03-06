import { useMemo } from "react";
import type { TaskStatistics } from "../../types/models";
import { KpiCard } from "./KpiCard";
import { useTranslation } from "react-i18next";

interface CostPerformanceTabProps {
  stats: TaskStatistics;
}

export function CostPerformanceTab({ stats }: CostPerformanceTabProps) {
  const { t } = useTranslation();
  const formatDuration = (ms: number | null): string => {
    if (ms === null) return "\u2014";
    if (ms < 1000) return `${Math.round(ms)}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  };

  // Find fastest agent
  const fastestAgent = useMemo(
    () => stats.byAgent
      .filter((a) => a.avgDurationMs !== null)
      .sort((a, b) => (a.avgDurationMs ?? Infinity) - (b.avgDurationMs ?? Infinity))[0],
    [stats.byAgent],
  );

  // Velocity: tasks completed per day over last 7 days
  const velocity = useMemo(() => {
    const last7 = stats.dailyCompleted.slice(-7);
    return last7.length > 0
      ? (last7.reduce((sum, d) => sum + d.count, 0) / 7).toFixed(1)
      : "0";
  }, [stats.dailyCompleted]);

  // Pre-compute maxDur for the bar chart
  const { agentsWithDuration, maxDur } = useMemo(() => {
    const filtered = stats.byAgent.filter((a) => a.avgDurationMs !== null);
    const max = Math.max(...filtered.map((a) => a.avgDurationMs!), 1);
    return { agentsWithDuration: filtered, maxDur: max };
  }, [stats.byAgent]);

  // Pre-compute maxCount for daily velocity chart
  const maxDailyCount = useMemo(
    () => Math.max(...stats.dailyCompleted.map((d) => d.count), 1),
    [stats.dailyCompleted],
  );

  const reversedDaily = useMemo(
    () => [...stats.dailyCompleted].reverse(),
    [stats.dailyCompleted],
  );

  return (
    <div className="space-y-4">
      {/* KPI cards */}
      <div className="grid grid-cols-3 gap-4">
        <KpiCard label={t("costs.performance.avgDuration")} value={formatDuration(stats.avgDurationMs)} />
        <KpiCard label={t("costs.performance.tasksPerDay")} value={velocity} />
        <KpiCard
          label={t("costs.performance.fastestAgent")}
          value={fastestAgent ? fastestAgent.agentType : "\u2014"}
        />
      </div>

      {/* Bar chart: avg duration by agent */}
      <div>
        <h3 className="text-xs font-medium text-zinc-400 mb-3">{t("costs.performance.avgDurationByAgent")}</h3>
        {stats.byAgent.length === 0 ? (
          <p className="text-xs text-zinc-500">{t("costs.taskStats.noData")}</p>
        ) : (
          <div className="space-y-2">
            {agentsWithDuration.map((agent) => (
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
                ))}
          </div>
        )}
      </div>

      {/* Daily velocity chart */}
      <div>
        <h3 className="text-xs font-medium text-zinc-400 mb-3">{t("costs.performance.tasksCompleted")}</h3>
        {stats.dailyCompleted.length === 0 ? (
          <p className="text-xs text-zinc-500">{t("costs.performance.noCompletions")}</p>
        ) : (
          <div className="space-y-1">
            <div className="flex items-end gap-1 h-32">
              {stats.dailyCompleted.map((day) => {
                const height = (day.count / maxDailyCount) * 100;
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
                <span>{t("costs.headers.date")}</span>
                <span className="text-right">{t("costs.performance.completed")}</span>
              </div>
              {reversedDaily.map((day) => (
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
