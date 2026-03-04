import { create } from "zustand";
import type { AppNotification } from "../types/models";
import * as api from "../tauri";

type ActionCallback = () => void;

interface NotificationStore {
  notifications: AppNotification[];
  unreadCount: number;
  toasts: AppNotification[];
  showPanel: boolean;
  actionCallbacks: Record<string, ActionCallback>;

  fetchNotifications: () => Promise<void>;
  fetchUnreadCount: () => Promise<void>;
  markRead: (id: string) => Promise<void>;
  markAllRead: () => Promise<void>;
  dismiss: (id: string) => Promise<void>;
  addToast: (notification: AppNotification) => void;
  addUndoToast: (label: string, undoFn: () => void) => void;
  removeToast: (id: string) => void;
  triggerAction: (actionId: string) => void;
  setShowPanel: (show: boolean) => void;
}

export const useNotificationStore = create<NotificationStore>((set, get) => ({
  notifications: [],
  unreadCount: 0,
  toasts: [],
  showPanel: false,
  actionCallbacks: {},

  fetchNotifications: async () => {
    const notifications = await api.listNotifications(50);
    set({ notifications });
  },

  fetchUnreadCount: async () => {
    const unreadCount = await api.getUnreadCount();
    set({ unreadCount });
  },

  markRead: async (id) => {
    await api.markNotificationRead(id);
    set((s) => ({
      notifications: s.notifications.map((n) =>
        n.id === id ? { ...n, isRead: true } : n,
      ),
      unreadCount: Math.max(0, s.unreadCount - 1),
    }));
  },

  markAllRead: async () => {
    await api.markAllNotificationsRead();
    set((s) => ({
      notifications: s.notifications.map((n) => ({ ...n, isRead: true })),
      unreadCount: 0,
    }));
  },

  dismiss: async (id) => {
    await api.dismissNotification(id);
    set((s) => ({
      notifications: s.notifications.filter((n) => n.id !== id),
      toasts: s.toasts.filter((t) => t.id !== id),
    }));
  },

  addToast: (notification) => {
    set((s) => {
      const toasts = [...s.toasts, notification].slice(-5);
      return { toasts };
    });
    // Auto-remove after 5s
    setTimeout(() => {
      get().removeToast(notification.id);
    }, 5000);
  },

  addUndoToast: (label, undoFn) => {
    const id = `undo-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const actionId = `action-${id}`;
    const notification: AppNotification = {
      id,
      category: "system",
      severity: "info",
      title: label,
      message: "Click Undo to reverse this action",
      metadata: null,
      isRead: false,
      isDismissed: false,
      createdAt: new Date().toISOString(),
      actionLabel: "Undo",
      actionId,
    };

    set((s) => ({
      toasts: [...s.toasts, notification].slice(-5),
      actionCallbacks: { ...s.actionCallbacks, [actionId]: undoFn },
    }));

    // Auto-remove after 10s (longer grace period for undo)
    setTimeout(() => {
      set((s) => {
        const { [actionId]: _, ...rest } = s.actionCallbacks;
        return { actionCallbacks: rest };
      });
      get().removeToast(id);
    }, 10000);
  },

  removeToast: (id) => {
    set((s) => ({
      toasts: s.toasts.filter((t) => t.id !== id),
    }));
  },

  triggerAction: (actionId) => {
    const callback = get().actionCallbacks[actionId];
    if (callback) {
      callback();
      // Remove the callback and the associated toast
      set((s) => {
        const { [actionId]: _, ...rest } = s.actionCallbacks;
        const toast = s.toasts.find((t) => t.actionId === actionId);
        return {
          actionCallbacks: rest,
          toasts: toast ? s.toasts.filter((t) => t.id !== toast.id) : s.toasts,
        };
      });
    }
  },

  setShowPanel: (show) => set({ showPanel: show }),
}));
