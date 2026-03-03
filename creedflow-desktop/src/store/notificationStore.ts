import { create } from "zustand";
import type { AppNotification } from "../types/models";
import * as api from "../tauri";

interface NotificationStore {
  notifications: AppNotification[];
  unreadCount: number;
  toasts: AppNotification[];
  showPanel: boolean;

  fetchNotifications: () => Promise<void>;
  fetchUnreadCount: () => Promise<void>;
  markRead: (id: string) => Promise<void>;
  markAllRead: () => Promise<void>;
  dismiss: (id: string) => Promise<void>;
  addToast: (notification: AppNotification) => void;
  removeToast: (id: string) => void;
  setShowPanel: (show: boolean) => void;
}

export const useNotificationStore = create<NotificationStore>((set, get) => ({
  notifications: [],
  unreadCount: 0,
  toasts: [],
  showPanel: false,

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

  removeToast: (id) => {
    set((s) => ({
      toasts: s.toasts.filter((t) => t.id !== id),
    }));
  },

  setShowPanel: (show) => set({ showPanel: show }),
}));
