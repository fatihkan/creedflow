import { useNotificationStore } from "../../store/notificationStore";
import {
  CheckCircle,
  AlertTriangle,
  XCircle,
  Info,
  X,
} from "lucide-react";
import type { NotificationSeverity } from "../../types/models";

const SEVERITY_CONFIG: Record<
  NotificationSeverity,
  { icon: typeof Info; color: string; bg: string; border: string }
> = {
  success: {
    icon: CheckCircle,
    color: "text-green-400",
    bg: "bg-green-950/80",
    border: "border-green-800/50",
  },
  warning: {
    icon: AlertTriangle,
    color: "text-amber-400",
    bg: "bg-amber-950/80",
    border: "border-amber-800/50",
  },
  error: {
    icon: XCircle,
    color: "text-red-400",
    bg: "bg-red-950/80",
    border: "border-red-800/50",
  },
  info: {
    icon: Info,
    color: "text-blue-400",
    bg: "bg-blue-950/80",
    border: "border-blue-800/50",
  },
};

export function ToastOverlay() {
  const toasts = useNotificationStore((s) => s.toasts);
  const removeToast = useNotificationStore((s) => s.removeToast);

  if (toasts.length === 0) return null;

  return (
    <div className="fixed top-4 right-4 z-50 flex flex-col gap-2 max-w-sm">
      {toasts.map((toast) => {
        const config = SEVERITY_CONFIG[toast.severity] || SEVERITY_CONFIG.info;
        const Icon = config.icon;

        return (
          <div
            key={toast.id}
            className={`flex items-start gap-2.5 p-3 rounded-lg border backdrop-blur-sm shadow-lg animate-in slide-in-from-right ${config.bg} ${config.border}`}
          >
            <Icon className={`w-4 h-4 mt-0.5 flex-shrink-0 ${config.color}`} />
            <div className="flex-1 min-w-0">
              <p className="text-xs font-medium text-zinc-200 truncate">
                {toast.title}
              </p>
              <p className="text-[11px] text-zinc-400 mt-0.5 line-clamp-2">
                {toast.message}
              </p>
            </div>
            <button
              onClick={() => removeToast(toast.id)}
              className="text-zinc-500 hover:text-zinc-300 flex-shrink-0"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        );
      })}
    </div>
  );
}
