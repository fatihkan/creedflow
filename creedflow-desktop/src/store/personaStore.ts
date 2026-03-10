import { create } from "zustand";
import type { AgentPersona } from "../types/models";
import * as api from "../tauri";

interface PersonaStore {
  personas: AgentPersona[];
  fetchPersonas: () => Promise<void>;
  createPersona: (
    name: string,
    description: string,
    systemPrompt: string,
    agentTypes: string[],
    tags: string[],
  ) => Promise<AgentPersona>;
  updatePersona: (
    id: string,
    name: string,
    description: string,
    systemPrompt: string,
    agentTypes: string[],
    tags: string[],
    isEnabled: boolean,
  ) => Promise<void>;
  deletePersona: (id: string) => Promise<void>;
}

export const usePersonaStore = create<PersonaStore>((set) => ({
  personas: [],

  fetchPersonas: async () => {
    try {
      const personas = await api.getAgentPersonas();
      set({ personas });
    } catch (e) {
      console.error("Failed to fetch personas:", e);
    }
  },

  createPersona: async (name, description, systemPrompt, agentTypes, tags) => {
    const persona = await api.createAgentPersona(
      name,
      description,
      systemPrompt,
      agentTypes,
      tags,
    );
    set((s) => ({ personas: [...s.personas, persona] }));
    return persona;
  },

  updatePersona: async (
    id,
    name,
    description,
    systemPrompt,
    agentTypes,
    tags,
    isEnabled,
  ) => {
    await api.updateAgentPersona(
      id,
      name,
      description,
      systemPrompt,
      agentTypes,
      tags,
      isEnabled,
    );
    set((s) => ({
      personas: s.personas.map((p) =>
        p.id === id
          ? {
              ...p,
              name,
              description,
              systemPrompt,
              agentTypes,
              tags,
              isEnabled,
            }
          : p,
      ),
    }));
  },

  deletePersona: async (id) => {
    await api.deleteAgentPersona(id);
    set((s) => ({ personas: s.personas.filter((p) => p.id !== id) }));
  },
}));
