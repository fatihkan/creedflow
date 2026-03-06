import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { Clock, Hammer, PauseCircle } from "lucide-react";
import * as api from "../../tauri";
import type { ProjectTimeStats as TimeStats } from "../../types/models";
import { showErrorToast } from "../../hooks/useErrorToast";

interface ProjectTimeStatsProps {
  projectId: string;
}

function formatDuration(ms: number): string {
  const totalSeconds = ms / 1000;
  if (totalSeconds < 60) return `${Math.round(totalSeconds)}s`;
  if (totalSeconds < 3600) {
    const m = Math.floor(totalSeconds / 60);
    const s = Math.floor(totalSeconds % 60);
    return `${m}m ${s}s`;
  }
  if (totalSeconds < 86400) {
    const h = Math.floor(totalSeconds / 3600);
    const m = Math.floor((totalSeconds % 3600) / 60);
    return `${h}h ${m}m`;
  }
  const d = Math.floor(totalSeconds / 86400);
  const h = Math.floor((totalSeconds % 86400) / 3600);
  return `${d}d ${h}h`;
}

export function ProjectTimeStats({ projectId }: ProjectTimeStatsProps) {
  const { t } = useTranslation();
  const [stats, setStats] = useState<TimeStats | null>(null);

  useEffect(() => {
    api.getProjectTimeStats(projectId).then(setStats).catch((e) => showErrorToast("Failed to load project time stats", e));
  }, [projectId]);

  if (!stats) return null;

  const maxMs = Math.max(...stats.agentBreakdown.map((a) => a.totalMs), 1);

  return (
    <div className="space-y-3">
      <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
        {t("projects.timeStats.title")}
      </label>

      <div className="grid grid-cols-3 gap-2">
        <TimeStat icon={Clock} label={t("projects.timeStats.elapsed")} value={formatDuration(stats.elapsedMs)} color="text-blue-400" />
        <TimeStat icon={Hammer} label={t("projects.timeStats.work")} value={formatDuration(stats.totalWorkMs)} color="text-green-400" />
        <TimeStat icon={PauseCircle} label={t("projects.timeStats.idle")} value={formatDuration(stats.idleMs)} color="text-zinc-400" />
      </div>

      {stats.agentBreakdown.length > 0 && (
        <div className="space-y-1.5">
          <span className="text-[10px] text-zinc-600">{t("projects.timeStats.perAgent")}</span>
          {stats.agentBreakdown.map((agent) => (
            <div key={agent.agentType} className="flex items-center gap-2">
              <span className="text-[10px] text-zinc-400 w-20 truncate capitalize">
                {agent.agentType}
              </span>
              <div className="flex-1 h-1.5 bg-zinc-800 rounded-full overflow-hidden">
                <div
                  className="h-full bg-amber-500/60 rounded-full"
                  style={{ width: `${(agent.totalMs / maxMs) * 100}%` }}
                />
              </div>
              <span className="text-[10px] text-zinc-500 font-mono w-16 text-right">
                {formatDuration(agent.totalMs)}
              </span>
              <span className="text-[10px] text-zinc-600 w-4 text-right">
                {agent.taskCount}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function TimeStat({
  icon: Icon,
  label,
  value,
  color,
}: {
  icon: React.FC<{ className?: string }>;
  label: string;
  value: string;
  color: string;
}) {
  return (
    <div className="p-2 bg-zinc-800/40 rounded-md text-center">
      <div className="flex items-center justify-center gap-1">
        <Icon className={`w-3 h-3 ${color}`} />
        <span className="text-[10px] text-zinc-500">{label}</span>
      </div>
      <p className={`text-sm font-bold font-mono mt-0.5 ${color}`}>{value}</p>
    </div>
  );
}
