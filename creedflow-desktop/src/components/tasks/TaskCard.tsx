import type { AgentTask } from "../../types/models";
import { AgentTypeBadge } from "../shared/AgentTypeBadge";
import { BackendBadge } from "../shared/BackendBadge";

interface Props {
  task: AgentTask;
  onClick: () => void;
}

export function TaskCard({ task, onClick }: Props) {
  return (
    <button
      onClick={onClick}
      className="w-full text-left p-2.5 bg-zinc-800/50 hover:bg-zinc-800 rounded-md border border-zinc-800 hover:border-zinc-700 transition-colors cursor-grab active:cursor-grabbing"
    >
      <p className="text-xs text-zinc-200 font-medium leading-snug line-clamp-2">
        {task.title}
      </p>
      <div className="flex items-center gap-1.5 mt-2 flex-wrap">
        <AgentTypeBadge agentType={task.agentType} />
        <BackendBadge backend={task.backend} />
        {task.costUsd != null && (
          <span className="text-[10px] text-zinc-500">
            ${task.costUsd.toFixed(4)}
          </span>
        )}
      </div>
    </button>
  );
}
