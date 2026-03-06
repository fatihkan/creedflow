import { create } from "zustand";
import type { CostSummary, BackendScore, CostBudget, BudgetUtilization } from "../types/models";
import * as api from "../tauri";

interface CostStore {
  summary: CostSummary | null;
  scores: BackendScore[];
  budgets: CostBudget[];
  utilizations: BudgetUtilization[];
  fetchSummary: () => Promise<void>;
  fetchScores: () => Promise<void>;
  fetchBudgets: () => Promise<void>;
  fetchUtilizations: () => Promise<void>;
  upsertBudget: (budget: CostBudget) => Promise<void>;
  deleteBudget: (id: string) => Promise<void>;
  acknowledgeAlert: (alertId: string) => Promise<void>;
}

export const useCostStore = create<CostStore>((set, get) => ({
  summary: null,
  scores: [],
  budgets: [],
  utilizations: [],

  fetchSummary: async () => {
    const summary = await api.getCostSummary();
    set({ summary });
  },

  fetchScores: async () => {
    const scores = await api.getBackendScores();
    set({ scores });
  },

  fetchBudgets: async () => {
    const budgets = await api.getCostBudgets();
    set({ budgets });
  },

  fetchUtilizations: async () => {
    const utilizations = await api.getBudgetUtilization();
    set({ utilizations });
  },

  upsertBudget: async (budget: CostBudget) => {
    await api.upsertCostBudget(budget);
    await get().fetchBudgets();
    await get().fetchUtilizations();
  },

  deleteBudget: async (id: string) => {
    await api.deleteCostBudget(id);
    await get().fetchBudgets();
    await get().fetchUtilizations();
  },

  acknowledgeAlert: async (alertId: string) => {
    await api.acknowledgeBudgetAlert(alertId);
    await get().fetchUtilizations();
  },
}));
