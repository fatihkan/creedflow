import { useState } from "react";
import { RotateCcw } from "lucide-react";
import type { AgentTask } from "../../types/models";
import * as api from "../../tauri";
import { useTaskStore } from "../../store/taskStore";
import { showErrorToast } from "../../hooks/useErrorToast";
import { useTranslation } from "react-i18next";

interface Props {
  task: AgentTask;
}

export function RevisionPromptSection({ task }: Props) {
  const { t } = useTranslation();
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
      showErrorToast("Failed to retry task", e);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
        {t("tasks.revision.title")}
      </label>
      <textarea
        value={revisionText}
        onChange={(e) => setRevisionText(e.target.value)}
        placeholder={t("tasks.revision.placeholder")}
        className="w-full mt-1 px-3 py-2 bg-zinc-900 border border-zinc-700 rounded-md text-sm text-zinc-300 resize-y min-h-[80px] placeholder:text-zinc-600"
      />
      <button
        onClick={handleRetry}
        disabled={loading}
        className="mt-2 flex items-center gap-1.5 px-3 py-1.5 text-xs bg-brand-600/20 text-brand-400 rounded-md hover:bg-brand-600/30 disabled:opacity-50"
      >
        <RotateCcw className="w-3 h-3" />
        {loading ? t("tasks.revision.retrying") : t("tasks.revision.saveRetry")}
      </button>
    </div>
  );
}
