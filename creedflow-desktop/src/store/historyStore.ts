import { create } from "zustand";

export interface UndoableCommand {
  label: string;
  execute: () => Promise<void>;
  undo: () => Promise<void>;
}

interface HistoryStore {
  past: UndoableCommand[];
  future: UndoableCommand[];
  canUndo: boolean;
  canRedo: boolean;
  push: (command: UndoableCommand) => Promise<void>;
  undo: () => Promise<void>;
  redo: () => Promise<void>;
}

const MAX_HISTORY = 50;

export const useHistoryStore = create<HistoryStore>((set, get) => ({
  past: [],
  future: [],
  canUndo: false,
  canRedo: false,

  push: async (command) => {
    await command.execute();
    set((s) => {
      const past = [...s.past, command].slice(-MAX_HISTORY);
      return { past, future: [], canUndo: true, canRedo: false };
    });
  },

  undo: async () => {
    const { past } = get();
    if (past.length === 0) return;
    const command = past[past.length - 1];
    await command.undo();
    set((s) => {
      const newPast = s.past.slice(0, -1);
      return {
        past: newPast,
        future: [command, ...s.future],
        canUndo: newPast.length > 0,
        canRedo: true,
      };
    });
  },

  redo: async () => {
    const { future } = get();
    if (future.length === 0) return;
    const command = future[0];
    await command.execute();
    set((s) => {
      const newFuture = s.future.slice(1);
      const newPast = [...s.past, command];
      return {
        past: newPast,
        future: newFuture,
        canUndo: true,
        canRedo: newFuture.length > 0,
      };
    });
  },
}));
