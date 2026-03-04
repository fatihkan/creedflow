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
