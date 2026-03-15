import { useCallback, useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  X,
  GitBranch,
  Clock,
  XCircle,
  FileText,
  Terminal,
  MessageSquare,
  MessageCircle,
  History,
} from "lucide-react";
import { useTaskStore } from "../../store/taskStore";
import { StatusBadge } from "../shared/StatusBadge";
import { BackendBadge } from "../shared/BackendBadge";
import { AgentTypeBadge } from "../shared/AgentTypeBadge";
import { RevisionPromptSection } from "../tasks/RevisionPromptSection";
import { TerminalOutput } from "../shared/TerminalOutput";
import { CodeDiffViewer, containsUnifiedDiff } from "../shared/CodeDiffViewer";
import { TaskComments } from "../tasks/TaskComments";
import { TaskPromptHistory } from "../tasks/TaskPromptHistory";
import * as api from "../../tauri";
import type { Review } from "../../types/models";
import { showErrorToast } from "../../hooks/useErrorToast";

type Tab = "info" | "output" | "reviews" | "comments" | "prompts";

interface DetailPanelProps {
  onClose: () => void;
}

export function DetailPanel({ onClose }: DetailPanelProps) {
  const { t } = useTranslation();
  const { selectedTaskId, tasks, updateTaskStatus } = useTaskStore();
  const task = useMemo(
    () => tasks.find((t) => t.id === selectedTaskId),
    [tasks, selectedTaskId],
  );
  const [tab, setTab] = useState<Tab>("info");
  const [reviews, setReviews] = useState<Review[]>([]);
  const [loadingReviews, setLoadingReviews] = useState(false);

  useEffect(() => {
    if (task?.id) {
      setLoadingReviews(true);
      api
        .listReviewsForTask(task.id)
        .then(setReviews)
        .catch((e) => showErrorToast("Failed to load reviews", e))
        .finally(() => setLoadingReviews(false));
    }
  }, [task?.id]);

  // Reset tab when task changes
  useEffect(() => {
    setTab("info");
  }, [selectedTaskId]);

  if (!task) {
    return (
      <div className="w-[400px] min-w-[340px] border-l border-zinc-800 bg-zinc-900/30 flex items-center justify-center text-zinc-500 text-sm">
        {t("tasks.detail.noSelection")}
      </div>
    );
  }

  const canCancel = task.status === "queued" || task.status === "in_progress";
  const isRunning = task.status === "in_progress";
  const duration = task.durationMs != null ? formatDuration(task.durationMs) : null;

  const handleCancel = useCallback(() => {
    updateTaskStatus(task.id, "cancelled");
  }, [task.id, updateTaskStatus]);

  const TABS: { id: Tab; label: string; icon: React.FC<{ className?: string }>; count?: number }[] = [
    { id: "info", label: t("tasks.detail.tabs.info"), icon: FileText },
    { id: "output", label: t("tasks.detail.tabs.output"), icon: Terminal },
    { id: "reviews", label: t("tasks.detail.tabs.reviews"), icon: MessageSquare, count: reviews.length },
    { id: "comments", label: t("tasks.detail.tabs.comments"), icon: MessageCircle },
    { id: "prompts", label: t("tasks.detail.tabs.prompts"), icon: History },
  ];

  return (
    <div className="w-[400px] min-w-[340px] border-l border-zinc-800 bg-zinc-900/30 flex flex-col overflow-hidden animate-slide-in-right">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <div className="flex items-center gap-2 min-w-0 flex-1 mr-2">
          <AgentTypeBadge agentType={task.agentType} />
          <StatusBadge status={task.status} />
        </div>
        <button
          onClick={onClose}
          className="p-1 text-zinc-500 hover:text-zinc-300 rounded flex-shrink-0"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Title */}
      <div className="px-4 py-2 border-b border-zinc-800/50">
        <h3 className="text-sm font-medium text-zinc-200">{task.title}</h3>
        {task.backend && (
          <div className="mt-1">
            <BackendBadge backend={task.backend} />
          </div>
        )}
      </div>

      {/* Tabs */}
      <div className="flex border-b border-zinc-800">
        {TABS.map(({ id, label, icon: Icon, count }) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            className={`flex items-center gap-1.5 px-3 py-2 text-xs font-medium transition-colors ${
              tab === id
                ? "text-brand-400 border-b-2 border-brand-400"
                : "text-zinc-500 hover:text-zinc-300"
            }`}
          >
            <Icon className="w-3.5 h-3.5" />
            {label}
            {count != null && count > 0 && (
              <span className="text-[10px] bg-zinc-800 px-1.5 py-0.5 rounded-full">{count}</span>
            )}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {tab === "info" && (
          <>
            {/* Description */}
            <div>
              <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
                {t("tasks.detail.description")}
              </label>
              <p className="text-sm text-zinc-300 mt-1 leading-relaxed">{task.description}</p>
            </div>

            {/* Metadata grid */}
            <div className="grid grid-cols-2 gap-3">
              <MetaField label={t("tasks.detail.priority")} value={`P${task.priority}`} />
              <MetaField label={t("tasks.detail.retries")} value={`${task.retryCount}/${task.maxRetries}`} />
              {duration && <MetaField label={t("tasks.detail.duration")} value={duration} icon={Clock} />}
              {task.costUsd != null && (
                <MetaField label={t("tasks.detail.cost")} value={`$${task.costUsd.toFixed(4)}`} />
              )}
            </div>

            {/* Branch */}
            {task.branchName && (
              <div className="flex items-center gap-2 px-3 py-2 bg-zinc-800/50 rounded-md">
                <GitBranch className="w-3.5 h-3.5 text-zinc-500" />
                <span className="text-xs text-zinc-300 font-mono">{task.branchName}</span>
                {task.prNumber != null && (
                  <span className="text-xs text-brand-400">PR #{task.prNumber}</span>
                )}
              </div>
            )}

            {/* Error */}
            {task.errorMessage && (
              <div className="px-3 py-2 bg-red-950/30 border border-red-900/30 rounded-md">
                <label className="text-[10px] font-medium text-red-500 uppercase tracking-wider">
                  {t("tasks.detail.error")}
                </label>
                <p className="text-xs text-red-400 mt-1">{task.errorMessage}</p>
              </div>
            )}

            {/* Actions */}
            <div className="flex items-center gap-2">
              {canCancel && (
                <button
                  onClick={handleCancel}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-red-600/20 text-red-400 rounded-md hover:bg-red-600/30 transition-colors"
                >
                  <XCircle className="w-3.5 h-3.5" />
                  {t("tasks.detail.cancelTask")}
                </button>
              )}
            </div>

            {/* Revision */}
            <RevisionPromptSection task={task} />
          </>
        )}

        {tab === "output" && (
          <OutputTab task={task} isRunning={isRunning} />
        )}

        {tab === "reviews" && (
          <div className="space-y-3">
            {loadingReviews ? (
              <p className="text-xs text-zinc-500">{t("tasks.detail.loadingReviews")}</p>
            ) : reviews.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-zinc-500">
                <MessageSquare className="w-8 h-8 mb-2 opacity-50" />
                <p className="text-xs">{t("tasks.detail.noReviews")}</p>
              </div>
            ) : (
              reviews.map((review) => (
                <ReviewCard key={review.id} review={review} />
              ))
            )}
          </div>
        )}

        {tab === "comments" && <TaskComments taskId={task.id} />}

        {tab === "prompts" && <TaskPromptHistory taskId={task.id} />}
      </div>
    </div>
  );
}

/* ─── Output Tab (diff detection) ─── */

function OutputTab({ task, isRunning }: { task: { id: string; result?: string | null; agentType: string }; isRunning: boolean }) {
  const { t } = useTranslation();
  const hasDiff = task.result ? containsUnifiedDiff(task.result) : false;
  const [showDiff, setShowDiff] = useState(hasDiff);

  useEffect(() => {
    setShowDiff(task.result ? containsUnifiedDiff(task.result) : false);
  }, [task.id, task.result]);

  if (!task.result && !isRunning) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-zinc-500">
        <Terminal className="w-8 h-8 mb-2 opacity-50" />
        <p className="text-xs">{t("tasks.detail.noOutput")}</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {hasDiff && (
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowDiff(!showDiff)}
            className={`text-[10px] px-2 py-1 rounded font-medium transition-colors ${
              showDiff
                ? "bg-blue-500/20 text-blue-400"
                : "bg-zinc-800 text-zinc-400 hover:text-zinc-300"
            }`}
          >
            {showDiff ? "Diff View" : "Raw Output"}
          </button>
        </div>
      )}
      {showDiff && task.result ? (
        <CodeDiffViewer content={task.result} />
      ) : (
        <TerminalOutput taskId={task.id} initialContent={task.result ?? undefined} />
      )}
    </div>
  );
}

/* ─── Sub-components ─── */

function MetaField({
  label,
  value,
  icon: Icon,
}: {
  label: string;
  value: string;
  icon?: React.FC<{ className?: string }>;
}) {
  return (
    <div>
      <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider flex items-center gap-1">
        {Icon && <Icon className="w-3 h-3" />}
        {label}
      </label>
      <p className="text-sm text-zinc-300 mt-0.5">{value}</p>
    </div>
  );
}

function ReviewCard({ review }: { review: Review }) {
  const { t } = useTranslation();
  const verdictColors: Record<string, string> = {
    pass: "bg-green-500/20 text-green-400",
    needsRevision: "bg-yellow-500/20 text-yellow-400",
    fail: "bg-red-500/20 text-red-400",
  };

  return (
    <div className="p-3 bg-zinc-800/50 rounded-lg border border-zinc-800 space-y-2">
      <div className="flex items-center justify-between">
        <span className={`text-[10px] font-medium px-2 py-0.5 rounded-full capitalize ${verdictColors[review.verdict] || "bg-zinc-700 text-zinc-400"}`}>
          {review.verdict}
        </span>
        {review.score != null && (
          <span className={`text-sm font-bold ${
            review.score >= 7 ? "text-green-400" : review.score >= 5 ? "text-yellow-400" : "text-red-400"
          }`}>
            {review.score}/10
          </span>
        )}
      </div>
      {review.summary && (
        <p className="text-xs text-zinc-300 leading-relaxed">{review.summary}</p>
      )}
      {review.issues && (
        <div>
          <label className="text-[10px] text-zinc-500 font-medium">{t("tasks.detail.issues")}</label>
          <p className="text-xs text-zinc-400 mt-0.5">{review.issues}</p>
        </div>
      )}
      {review.suggestions && (
        <div>
          <label className="text-[10px] text-zinc-500 font-medium">{t("tasks.detail.suggestions")}</label>
          <p className="text-xs text-zinc-400 mt-0.5">{review.suggestions}</p>
        </div>
      )}
    </div>
  );
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  const secs = Math.floor(ms / 1000);
  if (secs < 60) return `${secs}s`;
  const mins = Math.floor(secs / 60);
  const remainSecs = secs % 60;
  return `${mins}m ${remainSecs}s`;
}
