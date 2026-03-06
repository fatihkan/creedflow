import { describe, it, expect, vi, beforeEach } from "vitest";
import { useHistoryStore } from "../store/historyStore";

describe("historyStore", () => {
  beforeEach(() => {
    useHistoryStore.setState({
      past: [],
      future: [],
      canUndo: false,
      canRedo: false,
    });
  });

  it("starts with empty state", () => {
    const state = useHistoryStore.getState();
    expect(state.past).toEqual([]);
    expect(state.future).toEqual([]);
    expect(state.canUndo).toBe(false);
    expect(state.canRedo).toBe(false);
  });

  it("push executes command and adds to history", async () => {
    const execute = vi.fn();
    const undo = vi.fn();

    await useHistoryStore.getState().push({
      label: "Test",
      execute,
      undo,
    });

    expect(execute).toHaveBeenCalledOnce();
    const state = useHistoryStore.getState();
    expect(state.past).toHaveLength(1);
    expect(state.canUndo).toBe(true);
    expect(state.canRedo).toBe(false);
  });

  it("push clears future history", async () => {
    const cmd1 = { label: "A", execute: vi.fn(), undo: vi.fn() };
    const cmd2 = { label: "B", execute: vi.fn(), undo: vi.fn() };

    await useHistoryStore.getState().push(cmd1);
    await useHistoryStore.getState().undo();
    expect(useHistoryStore.getState().canRedo).toBe(true);

    await useHistoryStore.getState().push(cmd2);
    expect(useHistoryStore.getState().canRedo).toBe(false);
    expect(useHistoryStore.getState().future).toEqual([]);
  });

  it("undo calls undo and moves command to future", async () => {
    const undo = vi.fn();
    await useHistoryStore.getState().push({
      label: "Test",
      execute: vi.fn(),
      undo,
    });

    await useHistoryStore.getState().undo();

    expect(undo).toHaveBeenCalledOnce();
    const state = useHistoryStore.getState();
    expect(state.past).toHaveLength(0);
    expect(state.future).toHaveLength(1);
    expect(state.canUndo).toBe(false);
    expect(state.canRedo).toBe(true);
  });

  it("redo re-executes and moves command back to past", async () => {
    const execute = vi.fn();
    await useHistoryStore.getState().push({
      label: "Test",
      execute,
      undo: vi.fn(),
    });
    await useHistoryStore.getState().undo();

    await useHistoryStore.getState().redo();

    expect(execute).toHaveBeenCalledTimes(2);
    const state = useHistoryStore.getState();
    expect(state.past).toHaveLength(1);
    expect(state.future).toHaveLength(0);
    expect(state.canUndo).toBe(true);
    expect(state.canRedo).toBe(false);
  });

  it("undo does nothing when past is empty", async () => {
    await useHistoryStore.getState().undo();
    expect(useHistoryStore.getState().past).toEqual([]);
  });

  it("redo does nothing when future is empty", async () => {
    await useHistoryStore.getState().redo();
    expect(useHistoryStore.getState().future).toEqual([]);
  });

  it("caps history at 50 entries", async () => {
    for (let i = 0; i < 55; i++) {
      await useHistoryStore.getState().push({
        label: `Cmd ${i}`,
        execute: vi.fn(),
        undo: vi.fn(),
      });
    }

    expect(useHistoryStore.getState().past).toHaveLength(50);
  });
});
