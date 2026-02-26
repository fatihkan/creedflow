import { X } from "lucide-react";
import { useTaskStore } from "../../store/taskStore";
import { StatusBadge } from "../shared/StatusBadge";
import { BackendBadge } from "../shared/BackendBadge";
import { AgentTypeBadge } from "../shared/AgentTypeBadge";
import { RevisionPromptSection } from "../tasks/RevisionPromptSection";

interface DetailPanelProps {
  onClose: () => void;
}

export function DetailPanel({ onClose }: DetailPanelProps) {
  const { selectedTaskId, tasks } = useTaskStore();
  const task = tasks.find((t) => t.id === selectedTaskId);

  if (!task) {
    return (
      <div className="w-[380px] min-w-[320px] border-l border-zinc-800 bg-zinc-900/30 flex items-center justify-center text-zinc-500 text-sm">
        No task selected
      </div>
    );
  }

  return (
    <div className="w-[380px] min-w-[320px] border-l border-zinc-800 bg-zinc-900/30 flex flex-col overflow-hidden animate-slide-in-right">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <h3 className="text-sm font-medium text-zinc-200 truncate flex-1 mr-2">
          {task.title}
        </h3>
        <button
          onClick={onClose}
          className="p-1 text-zinc-500 hover:text-zinc-300 rounded flex-shrink-0"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Badges */}
        <div className="flex items-center gap-1.5 flex-wrap">
          <AgentTypeBadge agentType={task.agentType} />
          <StatusBadge status={task.status} />
          <BackendBadge backend={task.backend} />
        </div>

        {/* Description */}
        <div>
          <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
            Description
          </label>
          <p className="text-sm text-zinc-300 mt-1">{task.description}</p>
        </div>

        {/* Metadata grid */}
        <div className="grid grid-cols-2 gap-3">
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

        {/* Branch */}
        {task.branchName && (
          <div>
            <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Branch
            </label>
            <p className="text-xs text-zinc-400 font-mono mt-1">
              {task.branchName}
            </p>
          </div>
        )}

        {/* Result */}
        {task.result && (
          <div>
            <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              Result
            </label>
            <pre className="mt-1 text-xs text-zinc-400 bg-zinc-900 rounded p-2 overflow-x-auto max-h-[200px] whitespace-pre-wrap">
              {task.result}
            </pre>
          </div>
        )}

        {/* Error */}
        {task.errorMessage && (
          <div>
            <label className="text-[10px] font-medium text-red-500 uppercase tracking-wider">
              Error
            </label>
            <p className="text-sm text-red-400 mt-1">{task.errorMessage}</p>
          </div>
        )}

        {/* Revision Prompt */}
        <RevisionPromptSection task={task} />
      </div>
    </div>
  );
}
