import { create } from "zustand";
import type { Project } from "../types/models";
import { showErrorToast } from "../hooks/useErrorToast";
import * as api from "../tauri";

interface ProjectStore {
  projects: Project[];
  selectedProjectId: string | null;
  loading: boolean;
  hasMore: boolean;
  pageSize: number;
  fetchProjects: () => Promise<void>;
  fetchMoreProjects: () => Promise<void>;
  selectProject: (id: string | null) => void;
  createProject: (
    name: string,
    description: string,
    techStack: string,
    projectType: string,
  ) => Promise<Project>;
  deleteProject: (id: string) => Promise<void>;
}

export const useProjectStore = create<ProjectStore>((set, get) => ({
  projects: [],
  selectedProjectId: null,
  loading: false,
  hasMore: true,
  pageSize: 50,

  fetchProjects: async () => {
    set({ loading: true });
    try {
      const projects = await api.listProjects(50, 0);
      set({ projects, loading: false, hasMore: projects.length >= 50 });
    } catch (e) {
      showErrorToast("Failed to fetch projects", e);
      set({ loading: false });
    }
  },

  fetchMoreProjects: async () => {
    const { projects, pageSize } = get();
    try {
      const more = await api.listProjects(pageSize, projects.length);
      set((s) => ({
        projects: [...s.projects, ...more],
        hasMore: more.length >= pageSize,
      }));
    } catch (e) {
      showErrorToast("Failed to fetch more projects", e);
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
