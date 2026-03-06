import { create } from "zustand";
import type { AppSettings, BackendInfo } from "../types/models";
import * as api from "../tauri";

interface SettingsStore {
  settings: AppSettings | null;
  backends: BackendInfo[];
  fetchSettings: () => Promise<void>;
  updateSettings: (settings: AppSettings) => Promise<void>;
  fetchBackends: () => Promise<void>;
  toggleBackend: (backendType: string, enabled: boolean) => Promise<void>;
}

export const useSettingsStore = create<SettingsStore>((set) => ({
  settings: null,
  backends: [],

  fetchSettings: async () => {
    try {
      const settings = await api.getSettings();
      set({ settings });
    } catch (e) {
      console.error("Failed to fetch settings:", e);
    }
  },

  updateSettings: async (settings) => {
    await api.updateSettings(settings);
    set({ settings });
  },

  fetchBackends: async () => {
    const backends = await api.listBackends();
    set({ backends });
  },

  toggleBackend: async (backendType, enabled) => {
    await api.toggleBackend(backendType, enabled);
    set((s) => ({
      backends: s.backends.map((b) =>
        b.backendType === backendType ? { ...b, isEnabled: enabled } : b,
      ),
    }));
  },
}));
