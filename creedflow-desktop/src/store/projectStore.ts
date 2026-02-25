import { create } from "zustand";
import type { Project } from "../types/models";
import * as api from "../tauri";

interface ProjectStore {
  projects: Project[];
  selectedProjectId: string | null;
  loading: boolean;
  fetchProjects: () => Promise<void>;
  selectProject: (id: string | null) => void;
  createProject: (
    name: string,
    description: string,
    techStack: string,
    projectType: string,
  ) => Promise<Project>;
  deleteProject: (id: string) => Promise<void>;
}

export const useProjectStore = create<ProjectStore>((set) => ({
  projects: [],
  selectedProjectId: null,
  loading: false,

  fetchProjects: async () => {
    set({ loading: true });
    try {
      const projects = await api.listProjects();
      set({ projects, loading: false });
    } catch (e) {
      console.error("Failed to fetch projects:", e);
      set({ loading: false });
    }
  },

  selectProject: (id) => set({ selectedProjectId: id }),

  createProject: async (name, description, techStack, projectType) => {
    const project = await api.createProject(
      name,
      description,
      techStack,
      projectType,
    );
    set((s) => ({ projects: [project, ...s.projects] }));
    return project;
  },

  deleteProject: async (id) => {
    await api.deleteProject(id);
    set((s) => ({
      projects: s.projects.filter((p) => p.id !== id),
      selectedProjectId:
        s.selectedProjectId === id ? null : s.selectedProjectId,
    }));
  },
}));
