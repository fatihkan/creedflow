import { useEffect } from "react";
import { useSettingsStore } from "../store/settingsStore";

export function useBackendStatus() {
  const { backends, fetchBackends } = useSettingsStore();

  useEffect(() => {
    fetchBackends();
  }, [fetchBackends]);

  return backends;
}
