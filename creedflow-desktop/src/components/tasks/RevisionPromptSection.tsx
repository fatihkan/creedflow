import { useState } from "react";
import { RotateCcw } from "lucide-react";
import type { AgentTask } from "../../types/models";
import * as api from "../../tauri";
import { useTaskStore } from "../../store/taskStore";

interface Props {
  task: AgentTask;
}

export function RevisionPromptSection({ task }: Props) {
  const [revisionText, setRevisionText] = useState(task.revisionPrompt ?? "");
  const [loading, setLoading] = useState(false);
  const updateTask = useTaskStore((s) => s.updateTask);

  const canRetry =
    task.status === "failed" || task.status === "needs_revision";

  if (!canRetry) return null;

  const handleRetry = async () => {
    setLoading(true);
    try {
      await api.retryTaskWithRevision(
        task.id,
        revisionText.trim() || undefined,
      );
      updateTask({
        ...task,
        status: "queued",
        retryCount: task.retryCount + 1,
        revisionPrompt: revisionText.trim() || null,
      });
    } catch (e) {
      console.error("Failed to retry task:", e);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
        Revision Instructions
      </label>
      <textarea
        value={revisionText}
        onChange={(e) => setRevisionText(e.target.value)}
        placeholder="Add specific instructions for the retry..."
        className="w-full mt-1 px-3 py-2 bg-zinc-900 border border-zinc-700 rounded-md text-sm text-zinc-300 resize-y min-h-[80px] placeholder:text-zinc-600"
      />
      <button
        onClick={handleRetry}
        disabled={loading}
        className="mt-2 flex items-center gap-1.5 px-3 py-1.5 text-xs bg-brand-600/20 text-brand-400 rounded-md hover:bg-brand-600/30 disabled:opacity-50"
      >
        <RotateCcw className="w-3 h-3" />
        {loading ? "Retrying..." : "Save & Retry"}
      </button>
    </div>
  );
}
