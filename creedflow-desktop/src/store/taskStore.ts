import { create } from "zustand";
import type { AgentTask } from "../types/models";
import { useHistoryStore } from "./historyStore";
import { useNotificationStore } from "./notificationStore";
import { showErrorToast } from "../hooks/useErrorToast";
import * as api from "../tauri";

interface TaskStore {
  tasks: AgentTask[];
  archivedTasks: AgentTask[];
  selectedTaskId: string | null;
  selectedIds: Set<string>;
  selectionMode: boolean;
  loading: boolean;
  hasMore: boolean;
  hasMoreArchived: boolean;
  fetchTasks: (projectId: string) => Promise<void>;
  fetchMoreTasks: (projectId: string) => Promise<void>;
  fetchArchivedTasks: (projectId?: string) => Promise<void>;
  fetchMoreArchivedTasks: (projectId?: string) => Promise<void>;
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
  toggleSelection: (id: string) => void;
  setSelectionMode: (mode: boolean) => void;
  clearSelection: () => void;
  duplicateTask: (id: string) => Promise<void>;
  archiveSelected: () => Promise<void>;
  restoreSelected: () => Promise<void>;
  deleteSelected: () => Promise<void>;
  batchRetry: () => Promise<void>;
  batchCancel: () => Promise<void>;
}

export const useTaskStore = create<TaskStore>((set, get) => ({
  tasks: [],
  archivedTasks: [],
  selectedTaskId: null,
  selectedIds: new Set(),
  selectionMode: false,
  loading: false,
  hasMore: true,
  hasMoreArchived: true,

  fetchTasks: async (projectId) => {
    set({ loading: true });
    try {
      const tasks = await api.listTasks(projectId, 100, 0);
      set({ tasks, loading: false, hasMore: tasks.length >= 100 });
    } catch (e) {
      showErrorToast("Failed to fetch tasks", e);
      set({ loading: false });
    }
  },

  fetchMoreTasks: async (projectId) => {
    const { tasks } = get();
    try {
      const more = await api.listTasks(projectId, 100, tasks.length);
      set((s) => ({
        tasks: [...s.tasks, ...more],
        hasMore: more.length >= 100,
      }));
    } catch (e) {
      showErrorToast("Failed to fetch more tasks", e);
    }
  },

  fetchArchivedTasks: async (projectId?) => {
    try {
      const archivedTasks = await api.listArchivedTasks(projectId, 100, 0);
      set({ archivedTasks, hasMoreArchived: archivedTasks.length >= 100 });
    } catch (e) {
      showErrorToast("Failed to fetch archived tasks", e);
    }
  },

  fetchMoreArchivedTasks: async (projectId?) => {
    const { archivedTasks } = get();
    try {
      const more = await api.listArchivedTasks(projectId, 100, archivedTasks.length);
      set((s) => ({
        archivedTasks: [...s.archivedTasks, ...more],
        hasMoreArchived: more.length >= 100,
      }));
    } catch (e) {
      showErrorToast("Failed to fetch more archived tasks", e);
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
    const prevTask = get().tasks.find((t) => t.id === id);
    const prevStatus = prevTask?.status;
    await useHistoryStore.getState().push({
      label: `Change task status to ${status}`,
      execute: async () => {
        await api.updateTaskStatus(id, status);
        set((s) => ({
          tasks: s.tasks.map((t) =>
            t.id === id ? { ...t, status: status as AgentTask["status"] } : t,
          ),
        }));
      },
      undo: async () => {
        if (!prevStatus) return;
        await api.updateTaskStatus(id, prevStatus);
        set((s) => ({
          tasks: s.tasks.map((t) =>
            t.id === id ? { ...t, status: prevStatus as AgentTask["status"] } : t,
          ),
        }));
      },
    });
  },

  updateTask: (task) => {
    set((s) => ({
      tasks: s.tasks.map((t) => (t.id === task.id ? task : t)),
    }));
  },

  toggleSelection: (id) => {
    set((s) => {
      const next = new Set(s.selectedIds);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return { selectedIds: next };
    });
  },

  setSelectionMode: (mode) =>
    set({ selectionMode: mode, selectedIds: new Set() }),

  clearSelection: () => set({ selectedIds: new Set(), selectionMode: false }),

  duplicateTask: async (id) => {
    try {
      const task = await api.duplicateTask(id);
      set((s) => ({ tasks: [...s.tasks, task] }));
    } catch (e) {
      showErrorToast("Failed to duplicate task", e);
    }
  },

  archiveSelected: async () => {
    const ids = Array.from(get().selectedIds);
    if (ids.length === 0) return;
    const archivedTasks = get().tasks.filter((t) => ids.includes(t.id));
    await useHistoryStore.getState().push({
      label: `Archive ${ids.length} task(s)`,
      execute: async () => {
        await api.archiveTasks(ids);
        set((s) => ({
          tasks: s.tasks.filter((t) => !ids.includes(t.id)),
          selectedIds: new Set(),
          selectionMode: false,
        }));
      },
      undo: async () => {
        await api.restoreTasks(ids);
        set((s) => ({
          tasks: [...s.tasks, ...archivedTasks],
        }));
      },
    });
  },

  restoreSelected: async () => {
    const ids = Array.from(get().selectedIds);
    if (ids.length === 0) return;
    const restoredTasks = get().archivedTasks.filter((t) => ids.includes(t.id));
    await useHistoryStore.getState().push({
      label: `Restore ${ids.length} task(s)`,
      execute: async () => {
        await api.restoreTasks(ids);
        set((s) => ({
          archivedTasks: s.archivedTasks.filter((t) => !ids.includes(t.id)),
          selectedIds: new Set(),
          selectionMode: false,
        }));
      },
      undo: async () => {
        await api.archiveTasks(ids);
        set((s) => ({
          archivedTasks: [...s.archivedTasks, ...restoredTasks],
        }));
      },
    });
  },

  deleteSelected: async () => {
    const ids = Array.from(get().selectedIds);
    if (ids.length === 0) return;
    const deletedTasks = get().archivedTasks.filter((t) => ids.includes(t.id));

    // Soft-delete: remove from UI immediately
    set((s) => ({
      archivedTasks: s.archivedTasks.filter((t) => !s.selectedIds.has(t.id)),
      selectedIds: new Set(),
      selectionMode: false,
    }));

    // Grace period: show undo toast for 10s, then permanently delete
    let cancelled = false;
    useNotificationStore.getState().addUndoToast(
      `Deleted ${ids.length} task(s)`,
      () => {
        cancelled = true;
        // Restore tasks to archived list
        set((s) => ({
          archivedTasks: [...s.archivedTasks, ...deletedTasks],
        }));
      },
    );

    // Permanently delete after grace period
    setTimeout(async () => {
      if (!cancelled) {
        try {
          await api.permanentlyDeleteTasks(ids);
        } catch (e) {
          showErrorToast("Failed to permanently delete tasks", e);
        }
      }
    }, 10500);
  },

  batchRetry: async () => {
    const { selectedIds, tasks } = get();
    const retryable = ["failed", "needs_revision", "cancelled"];
    const ids = Array.from(selectedIds).filter((id) => {
      const t = tasks.find((task) => task.id === id);
      return t && retryable.includes(t.status);
    });
    if (ids.length === 0) return;
    await api.batchRetryTasks(ids);
    set((s) => ({
      tasks: s.tasks.map((t) =>
        ids.includes(t.id) ? { ...t, status: "queued" as const, retryCount: t.retryCount + 1 } : t,
      ),
      selectedIds: new Set(),
      selectionMode: false,
    }));
  },

  batchCancel: async () => {
    const { selectedIds, tasks } = get();
    const ids = Array.from(selectedIds).filter((id) => {
      const t = tasks.find((task) => task.id === id);
      return t && t.status === "queued";
    });
    if (ids.length === 0) return;
    await api.batchCancelTasks(ids);
    set((s) => ({
      tasks: s.tasks.map((t) =>
        ids.includes(t.id) ? { ...t, status: "cancelled" as const } : t,
      ),
      selectedIds: new Set(),
      selectionMode: false,
    }));
  },
}));
