import { useEffect, useState } from "react";
import { Send, User, Settings } from "lucide-react";
import * as api from "../../tauri";
import type { TaskComment } from "../../types/models";
import { showErrorToast } from "../../hooks/useErrorToast";
import { useTranslation } from "react-i18next";

interface TaskCommentsProps {
  taskId: string;
}

export function TaskComments({ taskId }: TaskCommentsProps) {
  const { t } = useTranslation();
  const [comments, setComments] = useState<TaskComment[]>([]);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);

  const fetchComments = () => {
    api.listTaskComments(taskId).then(setComments).catch((e) => showErrorToast("Failed to load comments", e));
  };

  useEffect(() => {
    fetchComments();
  }, [taskId]);

  const handleSend = async () => {
    const content = text.trim();
    if (!content) return;
    setSending(true);
    try {
      await api.addTaskComment(taskId, content);
      setText("");
      fetchComments();
    } catch (e) {
      showErrorToast("Failed to add comment", e);
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="space-y-2">
      <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
        {t("tasks.comments.title")} ({comments.length})
      </label>

      {comments.length === 0 ? (
        <p className="text-xs text-zinc-600 py-2">{t("tasks.comments.empty")}</p>
      ) : (
        <div className="space-y-1.5 max-h-48 overflow-y-auto">
          {comments.map((c) => (
            <div
              key={c.id}
              className={`flex gap-2 p-2 rounded-md ${
                c.author === "user"
                  ? "bg-blue-500/5 border border-blue-500/10"
                  : "bg-zinc-800/50"
              }`}
            >
              {c.author === "user" ? (
                <User className="w-3.5 h-3.5 text-blue-400 mt-0.5 flex-shrink-0" />
              ) : (
                <Settings className="w-3.5 h-3.5 text-zinc-500 mt-0.5 flex-shrink-0" />
              )}
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between">
                  <span className="text-[10px] font-medium text-zinc-400">
                    {c.author === "user" ? t("tasks.comments.you") : t("tasks.comments.system")}
                  </span>
                  <span className="text-[10px] text-zinc-600">{formatRelative(c.createdAt, t)}</span>
                </div>
                <p className="text-xs text-zinc-300 mt-0.5 whitespace-pre-wrap">{c.content}</p>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="flex gap-1.5">
        <input
          type="text"
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && handleSend()}
          placeholder={t("tasks.comments.placeholder")}
          className="flex-1 px-2 py-1.5 text-xs bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-zinc-600"
        />
        <button
          onClick={handleSend}
          disabled={!text.trim() || sending}
          className="px-2 py-1.5 bg-brand-600 text-white rounded-md hover:bg-brand-500 disabled:opacity-40 transition-colors"
        >
          <Send className="w-3.5 h-3.5" />
        </button>
      </div>
    </div>
  );
}

// formatRelative is kept as a module-level function; it receives `t` from the caller.
// However, since it's used inside JSX via {formatRelative(c.createdAt)}, we need to
// pass `t` or use a different approach. We'll convert it to accept a `t` function.
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
