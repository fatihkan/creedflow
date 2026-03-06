import { useEffect, useState } from "react";
import { FileText, CheckCircle, XCircle } from "lucide-react";
import * as api from "../../tauri";
import type { PromptUsageRecord } from "../../types/models";
import { showErrorToast } from "../../hooks/useErrorToast";
import { useTranslation } from "react-i18next";

interface TaskPromptHistoryProps {
  taskId: string;
}

export function TaskPromptHistory({ taskId }: TaskPromptHistoryProps) {
  const { t } = useTranslation();
  const [records, setRecords] = useState<PromptUsageRecord[]>([]);

  useEffect(() => {
    api.getTaskPromptHistory(taskId).then(setRecords).catch((e) => showErrorToast("Failed to load prompt history", e));
  }, [taskId]);

  return (
    <div className="space-y-2">
      <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
        {t("tasks.promptHistory.title")} ({records.length})
      </label>

      {records.length === 0 ? (
        <p className="text-xs text-zinc-600 py-2">{t("tasks.promptHistory.empty")}</p>
      ) : (
        <div className="space-y-1.5">
          {records.map((r) => (
            <div
              key={r.id}
              className="flex items-start gap-2 p-2 rounded-md bg-zinc-800/50"
            >
              <FileText className="w-3.5 h-3.5 text-zinc-500 mt-0.5 flex-shrink-0" />
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium text-zinc-300 truncate">
                    {r.promptTitle || t("tasks.promptHistory.untitled")}
                  </span>
                  {r.outcome && (
                    <span
                      className={`flex items-center gap-0.5 text-[10px] ${
                        r.outcome === "completed"
                          ? "text-green-400"
                          : "text-red-400"
                      }`}
                    >
                      {r.outcome === "completed" ? (
                        <CheckCircle className="w-3 h-3" />
                      ) : (
                        <XCircle className="w-3 h-3" />
                      )}
                      {r.outcome}
                    </span>
                  )}
                </div>
                <div className="flex items-center gap-2 mt-0.5">
                  {r.agentType && (
                    <span className="text-[10px] text-zinc-500">
                      {r.agentType}
                    </span>
                  )}
                  {r.reviewScore != null && (
                    <span
                      className={`text-[10px] font-medium ${
                        r.reviewScore >= 7
                          ? "text-green-400"
                          : r.reviewScore >= 5
                            ? "text-yellow-400"
                            : "text-red-400"
                      }`}
                    >
                      {r.reviewScore.toFixed(1)}/10
                    </span>
                  )}
                  <span className="text-[10px] text-zinc-600">
                    {formatRelative(r.usedAt, t)}
                  </span>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function formatRelative(dateStr: string, t: (key: string, opts?: Record<string, unknown>) => string): string {
  const date = new Date(dateStr + "Z");
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  if (diffMins < 1) return t("common.time.justNow");
  if (diffMins < 60) return t("common.time.minutesAgo", { count: diffMins });
  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return t("common.time.hoursAgo", { count: diffHours });
  const diffDays = Math.floor(diffHours / 24);
  return t("common.time.daysAgo", { count: diffDays });
}
