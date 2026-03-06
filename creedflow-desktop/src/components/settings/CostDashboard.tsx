import { useEffect, useState } from "react";
import { useCostStore } from "../../store/costStore";
import * as api from "../../tauri";
import type { CostBreakdown } from "../../tauri";
import type { TaskStatistics } from "../../types/models";
import { DollarSign, Cpu, Server, Calendar, BarChart3, Zap } from "lucide-react";
import { useTranslation } from "react-i18next";
import { showErrorToast } from "../../hooks/useErrorToast";
import { KpiCard } from "./KpiCard";
import { BreakdownTable } from "./BreakdownTable";
import { CostTimelineTab } from "./CostTimelineTab";
import { CostTasksTab } from "./CostTasksTab";
import { CostPerformanceTab } from "./CostPerformanceTab";

type Tab = "overview" | "agents" | "backends" | "timeline" | "tasks" | "performance";

export function CostDashboard() {
  const { t } = useTranslation();
  const { summary, fetchSummary } = useCostStore();
  const [tab, setTab] = useState<Tab>("overview");
  const [byAgent, setByAgent] = useState<CostBreakdown[]>([]);
  const [byBackend, setByBackend] = useState<CostBreakdown[]>([]);
  const [timeline, setTimeline] = useState<CostBreakdown[]>([]);
  const [taskStats, setTaskStats] = useState<TaskStatistics | null>(null);

  useEffect(() => {
    fetchSummary();
    api.getCostByAgent().then(setByAgent).catch((e) => showErrorToast("Failed to load cost by agent", e));
    api.getCostByBackend().then(setByBackend).catch((e) => showErrorToast("Failed to load cost by backend", e));
    api.getCostTimeline().then(setTimeline).catch((e) => showErrorToast("Failed to load cost timeline", e));
    api.getTaskStatistics().then(setTaskStats).catch((e) => showErrorToast("Failed to load task statistics", e));
  }, [fetchSummary]);

  return (
    <div className="flex-1 flex flex-col">
      <div className="px-4 py-3 border-b border-zinc-800">
        <h2 className="text-sm font-semibold text-zinc-200">{t("costs.title")}</h2>
      </div>

      {/* KPI cards */}
      <div className="p-4">
        <div className="grid grid-cols-3 gap-4">
          <KpiCard label={t("costs.totalCost")} value={`$${summary?.totalCost.toFixed(2) ?? "0.00"}`} />
          <KpiCard label={t("costs.tasksTracked")} value={String(summary?.totalTasks ?? 0)} />
          <KpiCard label={t("costs.totalTokens")} value={summary?.totalTokens?.toLocaleString() ?? "0"} />
        </div>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-zinc-800 px-4 overflow-x-auto">
        {([
          { id: "overview" as Tab, label: t("costs.tabs.overview"), icon: DollarSign },
          { id: "agents" as Tab, label: t("costs.tabs.byAgent"), icon: Cpu },
          { id: "backends" as Tab, label: t("costs.tabs.byBackend"), icon: Server },
          { id: "timeline" as Tab, label: t("costs.tabs.timeline"), icon: Calendar },
          { id: "tasks" as Tab, label: t("costs.tabs.tasks"), icon: BarChart3 },
          { id: "performance" as Tab, label: t("costs.tabs.performance"), icon: Zap },
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
            <BreakdownTable title={t("costs.topAgents")} data={byAgent.slice(0, 5)} />
            <BreakdownTable title={t("costs.topBackends")} data={byBackend.slice(0, 5)} />
          </div>
        )}

        {tab === "agents" && <BreakdownTable title={t("costs.costByAgent")} data={byAgent} />}
        {tab === "backends" && <BreakdownTable title={t("costs.costByBackend")} data={byBackend} />}

        {tab === "timeline" && (
          <CostTimelineTab timeline={timeline} />
        )}

        {tab === "tasks" && taskStats && <CostTasksTab stats={taskStats} />}
        {tab === "tasks" && !taskStats && (
          <p className="text-xs text-zinc-500">{t("costs.loadingStats")}</p>
        )}

        {tab === "performance" && taskStats && <CostPerformanceTab stats={taskStats} />}
        {tab === "performance" && !taskStats && (
          <p className="text-xs text-zinc-500">{t("costs.loadingPerformance")}</p>
        )}
      </div>
    </div>
  );
}
