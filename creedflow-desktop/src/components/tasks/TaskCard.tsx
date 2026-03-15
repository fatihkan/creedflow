import { useState } from "react";
import { Copy, Eye } from "lucide-react";
import type { AgentTask } from "../../types/models";
import { AgentTypeBadge } from "../shared/AgentTypeBadge";
import { BackendBadge } from "../shared/BackendBadge";
import { LiveTimer, formatDuration } from "../shared/LiveTimer";
import { TerminalOutput } from "../shared/TerminalOutput";
import { useTaskStore } from "../../store/taskStore";
import { useTranslation } from "react-i18next";

interface Props {
  task: AgentTask;
  onClick: () => void;
}

export function TaskCard({ task, onClick }: Props) {
  const duplicateTask = useTaskStore((s) => s.duplicateTask);
  const { t } = useTranslation();
  const [showPeek, setShowPeek] = useState(false);

  const handleDuplicate = (e: React.MouseEvent) => {
    e.stopPropagation();
    duplicateTask(task.id);
  };

  const handlePeek = (e: React.MouseEvent) => {
    e.stopPropagation();
    setShowPeek(!showPeek);
  };

  const isRunning = task.status === "in_progress";

  return (
    <div className="relative">
      <button
        onClick={onClick}
        className="w-full text-left p-2.5 bg-zinc-800/50 hover:bg-zinc-800 rounded-md border border-zinc-800 hover:border-zinc-700 transition-colors cursor-grab active:cursor-grabbing relative group"
      >
        <div className="absolute top-1.5 right-1.5 opacity-0 group-hover:opacity-100 transition-opacity flex gap-0.5">
          {isRunning && (
            <span
              role="button"
              onClick={handlePeek}
              className="p-1 text-zinc-500 hover:text-blue-400 hover:bg-zinc-700 rounded"
              title="Peek at live output"
            >
              <Eye className="w-3 h-3" />
            </span>
          )}
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
          {isRunning && task.startedAt ? (
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

      {/* Live output peek popover */}
      {showPeek && isRunning && (
        <div className="absolute z-50 left-0 right-0 top-full mt-1 bg-zinc-900 border border-zinc-700 rounded-lg shadow-xl overflow-hidden">
          <div className="flex items-center justify-between px-2 py-1 bg-zinc-800 border-b border-zinc-700">
            <span className="text-[10px] text-zinc-400 font-medium">Live Output</span>
            <button
              onClick={(e) => { e.stopPropagation(); setShowPeek(false); }}
              className="text-[10px] text-zinc-500 hover:text-zinc-300 px-1"
            >
              Close
            </button>
          </div>
          <div className="max-h-[200px] overflow-hidden">
            <TerminalOutput taskId={task.id} />
          </div>
        </div>
      )}
    </div>
  );
}
