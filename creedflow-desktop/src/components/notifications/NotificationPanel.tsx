import { useEffect } from "react";
import { useNotificationStore } from "../../store/notificationStore";
import {
  CheckCircle,
  AlertTriangle,
  XCircle,
  Info,
  X,
  CheckCheck,
  Bell,
  Trash2,
} from "lucide-react";
import type { AppNotification, NotificationSeverity, NotificationCategory } from "../../types/models";
import { FocusTrap } from "../shared/FocusTrap";
import { useTranslation } from "react-i18next";

const SEVERITY_ICON: Record<NotificationSeverity, typeof Info> = {
  success: CheckCircle,
  warning: AlertTriangle,
  error: XCircle,
  info: Info,
};

const SEVERITY_COLOR: Record<NotificationSeverity, string> = {
  success: "text-green-400",
  warning: "text-amber-400",
  error: "text-red-400",
  info: "text-blue-400",
};

// Category labels are resolved via t() at render time — see NotificationRow.

const CATEGORY_COLOR: Record<NotificationCategory, string> = {
  backendHealth: "bg-purple-500/20 text-purple-400",
  mcpHealth: "bg-cyan-500/20 text-cyan-400",
  rateLimit: "bg-orange-500/20 text-orange-400",
  task: "bg-blue-500/20 text-blue-400",
  deploy: "bg-green-500/20 text-green-400",
  system: "bg-zinc-500/20 text-zinc-400",
};

interface NotificationPanelProps {
  onClose: () => void;
}

export function NotificationPanel({ onClose }: NotificationPanelProps) {
  const { t } = useTranslation();
  const notifications = useNotificationStore((s) => s.notifications);
  const fetchNotifications = useNotificationStore((s) => s.fetchNotifications);
  const markRead = useNotificationStore((s) => s.markRead);
  const markAllRead = useNotificationStore((s) => s.markAllRead);
  const deleteNotification = useNotificationStore((s) => s.deleteNotification);
  const clearAll = useNotificationStore((s) => s.clearAll);
  const unreadCount = useNotificationStore((s) => s.unreadCount);

  useEffect(() => {
    fetchNotifications();
  }, [fetchNotifications]);

  return (
    <FocusTrap>
    <div className="w-[360px] max-h-[480px] bg-zinc-900 border border-zinc-800 rounded-lg shadow-xl flex flex-col overflow-hidden" role="dialog" aria-modal="true" aria-label="Notifications">
      {/* Header */}
      <div className="flex items-center justify-between p-3 border-b border-zinc-800">
        <div className="flex items-center gap-2">
          <Bell className="w-4 h-4 text-zinc-400" />
          <h3 className="text-sm font-semibold text-zinc-200">{t("notifications.title")}</h3>
          {unreadCount > 0 && (
            <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-brand-600/20 text-brand-400">
              {unreadCount}
            </span>
          )}
        </div>
        <div className="flex items-center gap-1">
          {unreadCount > 0 && (
            <button
              onClick={markAllRead}
              className="p-1 rounded text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800"
              title={t("notifications.markAllRead")}
              aria-label={t("notifications.markAllRead")}
            >
              <CheckCheck className="w-4 h-4" />
            </button>
          )}
          {notifications.length > 0 && (
            <button
              onClick={clearAll}
              className="p-1 rounded text-zinc-500 hover:text-red-400 hover:bg-zinc-800"
              title={t("notifications.clearAll")}
              aria-label={t("notifications.clearAll")}
            >
              <Trash2 className="w-4 h-4" />
            </button>
          )}
          <button
            onClick={onClose}
            className="p-1 rounded text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800"
            aria-label={t("notifications.close")}
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* List */}
      <div className="flex-1 overflow-y-auto">
        {notifications.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-32 text-zinc-600">
            <Bell className="w-6 h-6 mb-2" />
            <p className="text-xs">{t("notifications.empty")}</p>
          </div>
        ) : (
          <div className="divide-y divide-zinc-800/50">
            {notifications.map((notif) => (
              <NotificationRow
                key={notif.id}
                notification={notif}
                onRead={() => markRead(notif.id)}
                onDelete={() => deleteNotification(notif.id)}
              />
            ))}
          </div>
        )}
      </div>
    </div>
    </FocusTrap>
  );
}

function NotificationRow({
  notification,
  onRead,
  onDelete,
}: {
  notification: AppNotification;
  onRead: () => void;
  onDelete: () => void;
}) {
  const { t } = useTranslation();
  const Icon = SEVERITY_ICON[notification.severity] || Info;
  const iconColor = SEVERITY_COLOR[notification.severity] || "text-zinc-400";
  const catLabel = t(`notifications.categories.${notification.category}`, notification.category);
  const catColor = CATEGORY_COLOR[notification.category] || "bg-zinc-500/20 text-zinc-400";

  const timeAgo = getTimeAgo(notification.createdAt, t);

  return (
    <div
      className={`flex items-start gap-2.5 p-3 hover:bg-zinc-800/30 transition-colors cursor-pointer group ${
        !notification.isRead ? "bg-zinc-800/10" : ""
      }`}
      onClick={() => {
        if (!notification.isRead) onRead();
      }}
    >
      <Icon className={`w-4 h-4 mt-0.5 flex-shrink-0 ${iconColor}`} />
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5 mb-0.5">
          <span className={`text-[9px] px-1 py-0.5 rounded ${catColor}`}>
            {catLabel}
          </span>
          {!notification.isRead && (
            <span className="w-1.5 h-1.5 rounded-full bg-brand-500" />
          )}
        </div>
        <p className="text-xs font-medium text-zinc-200 truncate">
          {notification.title}
        </p>
        <p className="text-[11px] text-zinc-500 mt-0.5 line-clamp-2">
          {notification.message}
        </p>
        <p className="text-[10px] text-zinc-600 mt-1">{timeAgo}</p>
      </div>
      <button
        onClick={(e) => {
          e.stopPropagation();
          onDelete();
        }}
        className="p-0.5 rounded text-zinc-600 hover:text-red-400 transition-colors flex-shrink-0"
        title={t("notifications.delete")}
        aria-label={t("notifications.delete")}
      >
        <X className="w-3.5 h-3.5" />
      </button>
    </div>
  );
}

function getTimeAgo(dateStr: string, t: (key: string, opts?: Record<string, unknown>) => string): string {
  const now = Date.now();
  const then = new Date(dateStr + "Z").getTime();
  const diffMs = now - then;
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) return t("notifications.timeAgo.justNow");
  if (diffMin < 60) return t("notifications.timeAgo.minutesAgo", { count: diffMin });
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return t("notifications.timeAgo.hoursAgo", { count: diffHr });
  const diffDay = Math.floor(diffHr / 24);
  return t("notifications.timeAgo.daysAgo", { count: diffDay });
}
