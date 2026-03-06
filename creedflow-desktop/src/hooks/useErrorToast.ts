import { useCallback } from "react";
import { useNotificationStore } from "../store/notificationStore";

export function useErrorToast() {
  const addToast = useNotificationStore((s) => s.addToast);

  const withError = useCallback(
    async <T>(fn: () => Promise<T>): Promise<T | undefined> => {
      try {
        return await fn();
      } catch (err) {
        const message =
          err instanceof Error ? err.message : String(err);
        addToast({
          id: crypto.randomUUID(),
          category: "system",
          severity: "error",
          title: "Error",
          message,
          metadata: null,
          isRead: false,
          isDismissed: false,
          createdAt: new Date().toISOString(),
        });
        return undefined;
      }
    },
    [addToast],
  );

  return withError;
}

/**
 * Non-hook version for use in Zustand stores and other non-component contexts.
 * Call directly: showErrorToast("Failed to load", error)
 */
export function showErrorToast(title: string, error?: unknown) {
  const message =
    error instanceof Error
      ? error.message
      : typeof error === "string"
        ? error
        : "An unexpected error occurred";
  useNotificationStore.getState().addToast({
    id: crypto.randomUUID(),
    category: "system",
    severity: "error",
    title,
    message,
    metadata: null,
    isRead: false,
    isDismissed: false,
    createdAt: new Date().toISOString(),
  });
}
