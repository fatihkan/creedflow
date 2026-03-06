import { Copy } from "lucide-react";
import type { AgentTask } from "../../types/models";
import { AgentTypeBadge } from "../shared/AgentTypeBadge";
import { BackendBadge } from "../shared/BackendBadge";
import { LiveTimer, formatDuration } from "../shared/LiveTimer";
import { useTaskStore } from "../../store/taskStore";
import { useTranslation } from "react-i18next";

interface Props {
  task: AgentTask;
  onClick: () => void;
}

export function TaskCard({ task, onClick }: Props) {
  const duplicateTask = useTaskStore((s) => s.duplicateTask);
  const { t } = useTranslation();

  const handleDuplicate = (e: React.MouseEvent) => {
    e.stopPropagation();
    duplicateTask(task.id);
  };

  return (
    <button
      onClick={onClick}
      className="w-full text-left p-2.5 bg-zinc-800/50 hover:bg-zinc-800 rounded-md border border-zinc-800 hover:border-zinc-700 transition-colors cursor-grab active:cursor-grabbing relative group"
    >
      <div className="absolute top-1.5 right-1.5 opacity-0 group-hover:opacity-100 transition-opacity">
        <span
          role="button"
          onClick={handleDuplicate}
          className="p-1 text-zinc-500 hover:text-zinc-200 hover:bg-zinc-700 rounded"
          title={t("tasks.duplicateTask")}
        >
          <Copy className="w-3 h-3" />
        </span>
      </div>
      <p className="text-xs text-zinc-200 font-medium leading-snug line-clamp-2 pr-6">
        {task.title}
      </p>
      <div className="flex items-center gap-1.5 mt-2 flex-wrap">
        <AgentTypeBadge agentType={task.agentType} />
        <BackendBadge backend={task.backend} />
        {task.status === "in_progress" && task.startedAt ? (
          <LiveTimer since={task.startedAt} />
        ) : task.durationMs != null ? (
          <span className="text-[10px] font-mono text-zinc-500">
            {formatDuration(task.durationMs)}
          </span>
        ) : null}
        {task.costUsd != null && (
          <span className="text-[10px] text-zinc-500">
            ${task.costUsd.toFixed(4)}
          </span>
        )}
      </div>
    </button>
  );
}
