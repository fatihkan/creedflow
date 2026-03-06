import { useTranslation } from "react-i18next";
import type { TaskStatus } from "../../types/models";

const STATUS_STYLES: Record<
  TaskStatus,
  { bg: string; text: string }
> = {
  queued: { bg: "bg-zinc-700", text: "text-zinc-300" },
  in_progress: {
    bg: "bg-blue-900/50",
    text: "text-blue-400",
  },
  passed: { bg: "bg-green-900/50", text: "text-green-400" },
  failed: { bg: "bg-red-900/50", text: "text-red-400" },
  needs_revision: {
    bg: "bg-yellow-900/50",
    text: "text-yellow-400",
  },
  cancelled: {
    bg: "bg-zinc-800",
    text: "text-zinc-500",
  },
};

const STATUS_LABEL_KEYS: Record<TaskStatus, string> = {
  queued: "common.status.queued",
  in_progress: "common.status.inProgress",
  passed: "common.status.passed",
  failed: "common.status.failed",
  needs_revision: "common.status.needsRevision",
  cancelled: "common.status.cancelled",
};

export function StatusBadge({ status }: { status: TaskStatus }) {
  const { t } = useTranslation();
  const styles = STATUS_STYLES[status] ?? STATUS_STYLES.queued;
  const label = t(STATUS_LABEL_KEYS[status] ?? STATUS_LABEL_KEYS.queued);
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${styles.bg} ${styles.text}`}
    >
      {label}
    </span>
  );
}
