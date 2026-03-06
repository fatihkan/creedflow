import { useMemo } from "react";
import type { TaskStatistics } from "../../types/models";
import { KpiCard } from "./KpiCard";
import { useTranslation } from "react-i18next";

interface CostTasksTabProps {
  stats: TaskStatistics;
}

export function CostTasksTab({ stats }: CostTasksTabProps) {
  const { t } = useTranslation();

  const avgRetries = useMemo(
    () => stats.byAgent.length > 0
      ? stats.byAgent.reduce((sum, a) => sum + a.needsRevision, 0)
      : 0,
    [stats.byAgent],
  );

  const maxCount = useMemo(
    () => Math.max(...stats.byAgent.map((a) => a.total), 1),
    [stats.byAgent],
  );

  return (
    <div className="space-y-4">
      {/* KPI cards */}
      <div className="grid grid-cols-3 gap-4">
        <KpiCard label={t("costs.taskStats.totalTasks")} value={String(stats.totalTasks)} />
        <KpiCard label={t("costs.taskStats.successRate")} value={`${stats.successRate.toFixed(1)}%`} />
        <KpiCard label={t("costs.taskStats.needsRevision")} value={String(avgRetries)} />
      </div>

      {/* Bar chart: passed vs failed by agent */}
      <div>
        <h3 className="text-xs font-medium text-zinc-400 mb-3">{t("costs.taskStats.successFailure")}</h3>
        {stats.byAgent.length === 0 ? (
          <p className="text-xs text-zinc-500">{t("costs.taskStats.noData")}</p>
        ) : (
          <div className="space-y-2">
            {stats.byAgent.map((agent) => (
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
              ))}
            <div className="flex gap-4 mt-2">
              <span className="flex items-center gap-1 text-[10px] text-zinc-500">
                <span className="w-2 h-2 rounded-sm bg-green-500/60" /> {t("costs.taskStats.passed")}
              </span>
              <span className="flex items-center gap-1 text-[10px] text-zinc-500">
                <span className="w-2 h-2 rounded-sm bg-red-500/60" /> {t("costs.taskStats.failed")}
              </span>
              <span className="flex items-center gap-1 text-[10px] text-zinc-500">
                <span className="w-2 h-2 rounded-sm bg-yellow-500/60" /> {t("costs.taskStats.revision")}
              </span>
            </div>
          </div>
        )}
      </div>

      {/* Table */}
      <div>
        <h3 className="text-xs font-medium text-zinc-400 mb-2">{t("costs.taskStats.byAgentType")}</h3>
        {stats.byAgent.length === 0 ? (
          <p className="text-xs text-zinc-500">{t("costs.taskStats.noData")}</p>
        ) : (
          <div className="space-y-1">
            <div className="grid grid-cols-[1fr_60px_60px_60px_60px_80px] gap-2 px-3 py-1 text-[10px] text-zinc-500 uppercase tracking-wider">
              <span>{t("costs.taskStats.agent")}</span>
              <span className="text-right">{t("costs.taskStats.total")}</span>
              <span className="text-right">{t("costs.taskStats.passed")}</span>
              <span className="text-right">{t("costs.taskStats.failed")}</span>
              <span className="text-right">{t("costs.taskStats.revision")}</span>
              <span className="text-right">{t("costs.taskStats.rate")}</span>
            </div>
            {stats.byAgent.map((agent) => {
              const completed = agent.passed + agent.failed;
              const rate = completed > 0 ? ((agent.passed / completed) * 100).toFixed(0) : "\u2014";
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
