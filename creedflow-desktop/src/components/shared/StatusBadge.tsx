import type { TaskStatus } from "../../types/models";

const STATUS_CONFIG: Record<
  TaskStatus,
  { label: string; bg: string; text: string }
> = {
  queued: { label: "Queued", bg: "bg-zinc-700", text: "text-zinc-300" },
  in_progress: {
    label: "In Progress",
    bg: "bg-blue-900/50",
    text: "text-blue-400",
  },
  passed: { label: "Passed", bg: "bg-green-900/50", text: "text-green-400" },
  failed: { label: "Failed", bg: "bg-red-900/50", text: "text-red-400" },
  needs_revision: {
    label: "Needs Revision",
    bg: "bg-yellow-900/50",
    text: "text-yellow-400",
  },
  cancelled: {
    label: "Cancelled",
    bg: "bg-zinc-800",
    text: "text-zinc-500",
  },
};

export function StatusBadge({ status }: { status: TaskStatus }) {
  const config = STATUS_CONFIG[status] ?? STATUS_CONFIG.queued;
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${config.bg} ${config.text}`}
    >
      {config.label}
    </span>
  );
}
