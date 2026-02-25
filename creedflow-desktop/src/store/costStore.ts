import { create } from "zustand";
import type { CostSummary } from "../types/models";
import * as api from "../tauri";

interface CostStore {
  summary: CostSummary | null;
  fetchSummary: () => Promise<void>;
}

export const useCostStore = create<CostStore>((set) => ({
  summary: null,

  fetchSummary: async () => {
    const summary = await api.getCostSummary();
    set({ summary });
  },
}));
