import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";

export interface Prompt {
  id: string;
  title: string;
  content: string;
  source: string;
  category: string;
  contributor: string | null;
  isBuiltIn: boolean;
  isFavorite: boolean;
  version: number;
  createdAt: string;
  updatedAt: string;
}

interface PromptStore {
  prompts: Prompt[];
  loading: boolean;
  filter: {
    category: string | null;
    source: string | null;
    search: string;
    favoritesOnly: boolean;
  };

  fetchPrompts: () => Promise<void>;
  createPrompt: (title: string, content: string, category: string) => Promise<void>;
  deletePrompt: (id: string) => Promise<void>;
  toggleFavorite: (id: string) => Promise<void>;
  setFilter: (filter: Partial<PromptStore["filter"]>) => void;
  filteredPrompts: () => Prompt[];
}

export const usePromptStore = create<PromptStore>((set, get) => ({
  prompts: [],
  loading: false,
  filter: {
    category: null,
    source: null,
    search: "",
    favoritesOnly: false,
  },

  fetchPrompts: async () => {
    set({ loading: true });
    try {
      const prompts = await invoke<Prompt[]>("list_prompts");
      set({ prompts, loading: false });
    } catch (e) {
      console.error("Failed to fetch prompts:", e);
      set({ loading: false });
    }
  },

  createPrompt: async (title, content, category) => {
    try {
      await invoke("create_prompt", { title, content, category });
      await get().fetchPrompts();
    } catch (e) {
      console.error("Failed to create prompt:", e);
      throw e;
    }
  },

  deletePrompt: async (id) => {
    try {
      await invoke("delete_prompt", { id });
      set((state) => ({
        prompts: state.prompts.filter((p) => p.id !== id),
      }));
    } catch (e) {
      console.error("Failed to delete prompt:", e);
    }
  },

  toggleFavorite: async (id) => {
    try {
      await invoke("toggle_favorite", { id });
      set((state) => ({
        prompts: state.prompts.map((p) =>
          p.id === id ? { ...p, isFavorite: !p.isFavorite } : p,
        ),
      }));
    } catch (e) {
      console.error("Failed to toggle favorite:", e);
    }
  },

  setFilter: (filter) => {
    set((state) => ({
      filter: { ...state.filter, ...filter },
    }));
  },

  filteredPrompts: () => {
    const { prompts, filter } = get();
    return prompts.filter((p) => {
      if (filter.category && p.category !== filter.category) return false;
      if (filter.source && p.source !== filter.source) return false;
      if (filter.favoritesOnly && !p.isFavorite) return false;
      if (
        filter.search &&
        !p.title.toLowerCase().includes(filter.search.toLowerCase()) &&
        !p.content.toLowerCase().includes(filter.search.toLowerCase())
      )
        return false;
      return true;
    });
  },
}));
