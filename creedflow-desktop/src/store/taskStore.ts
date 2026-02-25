import { create } from "zustand";
import type { AgentTask } from "../types/models";
import * as api from "../tauri";

interface TaskStore {
  tasks: AgentTask[];
  selectedTaskId: string | null;
  loading: boolean;
  fetchTasks: (projectId: string) => Promise<void>;
  selectTask: (id: string | null) => void;
  createTask: (
    projectId: string,
    title: string,
    description: string,
    agentType: string,
    priority?: number,
  ) => Promise<AgentTask>;
  updateTaskStatus: (id: string, status: string) => Promise<void>;
  updateTask: (task: AgentTask) => void;
}

export const useTaskStore = create<TaskStore>((set) => ({
  tasks: [],
  selectedTaskId: null,
  loading: false,

  fetchTasks: async (projectId) => {
    set({ loading: true });
    try {
      const tasks = await api.listTasks(projectId);
      set({ tasks, loading: false });
    } catch (e) {
      console.error("Failed to fetch tasks:", e);
      set({ loading: false });
    }
  },

  selectTask: (id) => set({ selectedTaskId: id }),

  createTask: async (projectId, title, description, agentType, priority) => {
    const task = await api.createTask(
      projectId,
      title,
      description,
      agentType,
      priority,
    );
    set((s) => ({ tasks: [...s.tasks, task] }));
    return task;
  },

  updateTaskStatus: async (id, status) => {
    await api.updateTaskStatus(id, status);
    set((s) => ({
      tasks: s.tasks.map((t) => (t.id === id ? { ...t, status: status as AgentTask["status"] } : t)),
    }));
  },

  updateTask: (task) => {
    set((s) => ({
      tasks: s.tasks.map((t) => (t.id === task.id ? task : t)),
    }));
  },
}));
