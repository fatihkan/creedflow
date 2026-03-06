import { describe, it, expect, vi, beforeEach } from "vitest";
import { useNotificationStore } from "../store/notificationStore";
import type { AppNotification } from "../types/models";

vi.mock("../tauri", () => ({
  listNotifications: vi.fn(),
  getUnreadCount: vi.fn(),
  markNotificationRead: vi.fn(),
  markAllNotificationsRead: vi.fn(),
  dismissNotification: vi.fn(),
  deleteNotification: vi.fn(),
  clearAllNotifications: vi.fn(),
}));

import * as api from "../tauri";

const mockNotification = (
  overrides: Partial<AppNotification> = {},
): AppNotification => ({
  id: "n1",
  category: "system",
  severity: "info",
  title: "Test Notification",
  message: "Test message",
  metadata: null,
  isRead: false,
  isDismissed: false,
  createdAt: "2024-01-01T00:00:00Z",
  ...overrides,
});

describe("notificationStore", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    useNotificationStore.setState({
      notifications: [],
      unreadCount: 0,
      toasts: [],
      showPanel: false,
      actionCallbacks: {},
    });
  });

  it("starts with empty state", () => {
    const state = useNotificationStore.getState();
    expect(state.notifications).toEqual([]);
    expect(state.unreadCount).toBe(0);
    expect(state.toasts).toEqual([]);
  });

  it("fetchNotifications loads notifications", async () => {
    const notifications = [mockNotification()];
    vi.mocked(api.listNotifications).mockResolvedValue(notifications);

    await useNotificationStore.getState().fetchNotifications();

    expect(api.listNotifications).toHaveBeenCalledWith(50);
    expect(useNotificationStore.getState().notifications).toHaveLength(1);
  });

  it("fetchUnreadCount updates count", async () => {
    vi.mocked(api.getUnreadCount).mockResolvedValue(5);

    await useNotificationStore.getState().fetchUnreadCount();

    expect(useNotificationStore.getState().unreadCount).toBe(5);
  });

  it("markRead updates notification and decrements count", async () => {
    useNotificationStore.setState({
      notifications: [mockNotification({ id: "n1", isRead: false })],
      unreadCount: 3,
    });
    vi.mocked(api.markNotificationRead).mockResolvedValue(undefined);

    await useNotificationStore.getState().markRead("n1");

    const state = useNotificationStore.getState();
    expect(state.notifications[0].isRead).toBe(true);
    expect(state.unreadCount).toBe(2);
  });

  it("markAllRead marks all notifications read", async () => {
    useNotificationStore.setState({
      notifications: [
        mockNotification({ id: "n1", isRead: false }),
        mockNotification({ id: "n2", isRead: false }),
      ],
      unreadCount: 2,
    });
    vi.mocked(api.markAllNotificationsRead).mockResolvedValue(undefined);

    await useNotificationStore.getState().markAllRead();

    const state = useNotificationStore.getState();
    expect(state.notifications.every((n) => n.isRead)).toBe(true);
    expect(state.unreadCount).toBe(0);
  });

  it("dismiss removes notification from both lists", async () => {
    const notif = mockNotification({ id: "n1" });
    useNotificationStore.setState({
      notifications: [notif],
      toasts: [notif],
    });
    vi.mocked(api.dismissNotification).mockResolvedValue(undefined);

    await useNotificationStore.getState().dismiss("n1");

    expect(useNotificationStore.getState().notifications).toHaveLength(0);
    expect(useNotificationStore.getState().toasts).toHaveLength(0);
  });

  it("deleteNotification removes and adjusts unread count", async () => {
    useNotificationStore.setState({
      notifications: [mockNotification({ id: "n1", isRead: false })],
      unreadCount: 1,
    });
    vi.mocked(api.deleteNotification).mockResolvedValue(undefined);

    await useNotificationStore.getState().deleteNotification("n1");

    expect(useNotificationStore.getState().notifications).toHaveLength(0);
    expect(useNotificationStore.getState().unreadCount).toBe(0);
  });

  it("clearAll empties everything", async () => {
    useNotificationStore.setState({
      notifications: [mockNotification()],
      unreadCount: 5,
    });
    vi.mocked(api.clearAllNotifications).mockResolvedValue(undefined);

    await useNotificationStore.getState().clearAll();

    const state = useNotificationStore.getState();
    expect(state.notifications).toEqual([]);
    expect(state.unreadCount).toBe(0);
  });

  it("addToast appends and caps at 5", () => {
    for (let i = 0; i < 7; i++) {
      useNotificationStore.getState().addToast(
        mockNotification({ id: `toast-${i}` }),
      );
    }

    expect(useNotificationStore.getState().toasts).toHaveLength(5);
    // Should keep the 5 most recent
    expect(useNotificationStore.getState().toasts[0].id).toBe("toast-2");
  });

  it("addToast auto-removes after 5s", () => {
    useNotificationStore.getState().addToast(mockNotification({ id: "auto" }));
    expect(useNotificationStore.getState().toasts).toHaveLength(1);

    vi.advanceTimersByTime(5000);

    expect(useNotificationStore.getState().toasts).toHaveLength(0);
  });

  it("addUndoToast creates toast with action", () => {
    const undoFn = vi.fn();
    useNotificationStore.getState().addUndoToast("Deleted item", undoFn);

    const toasts = useNotificationStore.getState().toasts;
    expect(toasts).toHaveLength(1);
    expect(toasts[0].title).toBe("Deleted item");
    expect(toasts[0].actionLabel).toBe("Undo");
  });

  it("triggerAction calls callback and cleans up", () => {
    const undoFn = vi.fn();
    useNotificationStore.getState().addUndoToast("Test", undoFn);

    const toast = useNotificationStore.getState().toasts[0];
    useNotificationStore.getState().triggerAction(toast.actionId!);

    expect(undoFn).toHaveBeenCalledOnce();
    expect(useNotificationStore.getState().toasts).toHaveLength(0);
    expect(
      Object.keys(useNotificationStore.getState().actionCallbacks),
    ).toHaveLength(0);
  });

  it("setShowPanel toggles panel", () => {
    useNotificationStore.getState().setShowPanel(true);
    expect(useNotificationStore.getState().showPanel).toBe(true);

    useNotificationStore.getState().setShowPanel(false);
    expect(useNotificationStore.getState().showPanel).toBe(false);
  });
});
