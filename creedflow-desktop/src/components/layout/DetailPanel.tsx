import { X } from "lucide-react";
import { useTaskStore } from "../../store/taskStore";
import { StatusBadge } from "../shared/StatusBadge";
import { BackendBadge } from "../shared/BackendBadge";
import { AgentTypeBadge } from "../shared/AgentTypeBadge";

interface DetailPanelProps {
  onClose: () => void;
}

export function DetailPanel({ onClose }: DetailPanelProps) {
  const { selectedTaskId, tasks } = useTaskStore();
  const task = tasks.find((t) => t.id === selectedTaskId);

  if (!task) {
    return (
      <div className="h-[280px] border-t border-zinc-800 bg-zinc-900/30 flex items-center justify-center text-zinc-500 text-sm">
        No task selected
      </div>
    );
  }

  return (
    <div className="h-[280px] border-t border-zinc-800 bg-zinc-900/30 flex flex-col overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-2 border-b border-zinc-800">
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-medium text-zinc-200 truncate max-w-[400px]">
            {task.title}
          </h3>
          <AgentTypeBadge agentType={task.agentType} />
          <StatusBadge status={task.status} />
          <BackendBadge backend={task.backend} />
        </div>
        <button
          onClick={onClose}
          className="p-1 text-zinc-500 hover:text-zinc-300 rounded"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        <div>
          <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
            Description
          </label>
          <p className="text-sm text-zinc-300 mt-1">{task.description}</p>
        </div>

        <div className="grid grid-cols-4 gap-3">
          <div>
            <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Priority
            </label>
            <p className="text-sm text-zinc-300">{task.priority}</p>
          </div>
          <div>
            <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Retries
            </label>
            <p className="text-sm text-zinc-300">
              {task.retryCount}/{task.maxRetries}
            </p>
          </div>
          <div>
            <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Cost
            </label>
            <p className="text-sm text-zinc-300">
              {task.costUsd != null ? `$${task.costUsd.toFixed(4)}` : "-"}
            </p>
          </div>
          <div>
            <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Duration
            </label>
            <p className="text-sm text-zinc-300">
              {task.durationMs != null
                ? `${(task.durationMs / 1000).toFixed(1)}s`
                : "-"}
            </p>
          </div>
        </div>

        {task.result && (
          <div>
            <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Result
            </label>
            <pre className="mt-1 text-xs text-zinc-400 bg-zinc-900 rounded p-2 overflow-x-auto max-h-[100px]">
              {task.result}
            </pre>
          </div>
        )}

        {task.errorMessage && (
          <div>
            <label className="text-[10px] font-medium text-red-500 uppercase tracking-wider">
              Error
            </label>
            <p className="text-sm text-red-400 mt-1">{task.errorMessage}</p>
          </div>
        )}
      </div>
    </div>
  );
}
