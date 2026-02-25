import { create } from "zustand";
import type { AgentTypeInfo } from "../types/models";
import * as api from "../tauri";

interface AgentStore {
  agentTypes: AgentTypeInfo[];
  fetchAgentTypes: () => Promise<void>;
}

export const useAgentStore = create<AgentStore>((set) => ({
  agentTypes: [],

  fetchAgentTypes: async () => {
    const agentTypes = await api.listAgentTypes();
    set({ agentTypes });
  },
}));
