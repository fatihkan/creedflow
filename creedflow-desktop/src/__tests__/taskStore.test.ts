import { describe, it, expect, vi, beforeEach } from "vitest";
import { useTaskStore } from "../store/taskStore";
import { useHistoryStore } from "../store/historyStore";
import type { AgentTask } from "../types/models";

vi.mock("../tauri", () => ({
  listTasks: vi.fn(),
  listArchivedTasks: vi.fn(),
  createTask: vi.fn(),
  updateTaskStatus: vi.fn(),
  duplicateTask: vi.fn(),
  archiveTasks: vi.fn(),
  restoreTasks: vi.fn(),
  permanentlyDeleteTasks: vi.fn(),
  batchRetryTasks: vi.fn(),
  batchCancelTasks: vi.fn(),
}));

import * as api from "../tauri";

const mockTask = (overrides: Partial<AgentTask> = {}): AgentTask => ({
  id: "t1",
  projectId: "p1",
  featureId: null,
  agentType: "coder",
  title: "Test Task",
  description: "A test task",
  priority: 5,
  status: "queued",
  result: null,
  errorMessage: null,
  retryCount: 0,
  maxRetries: 3,
  sessionId: null,
  branchName: null,
  prNumber: null,
  costUsd: null,
  durationMs: null,
  createdAt: "2024-01-01T00:00:00Z",
  updatedAt: "2024-01-01T00:00:00Z",
  startedAt: null,
  completedAt: null,
  backend: null,
  promptChainId: null,
  revisionPrompt: null,
  skillPersona: null,
  archivedAt: null,
  ...overrides,
});

describe("taskStore", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useTaskStore.setState({
      tasks: [],
      archivedTasks: [],
      selectedTaskId: null,
      selectedIds: new Set(),
      selectionMode: false,
      loading: false,
      hasMore: true,
      hasMoreArchived: true,
    });
    useHistoryStore.setState({
      past: [],
      future: [],
      canUndo: false,
      canRedo: false,
    });
  });

  it("starts with empty state", () => {
    const state = useTaskStore.getState();
    expect(state.tasks).toEqual([]);
    expect(state.selectedTaskId).toBeNull();
    expect(state.loading).toBe(false);
  });

  it("fetchTasks loads tasks with pagination params", async () => {
    const tasks = [mockTask({ id: "t1" }), mockTask({ id: "t2" })];
    vi.mocked(api.listTasks).mockResolvedValue(tasks);

    await useTaskStore.getState().fetchTasks("p1");

    expect(api.listTasks).toHaveBeenCalledWith("p1", 100, 0);
    expect(useTaskStore.getState().tasks).toHaveLength(2);
    expect(useTaskStore.getState().loading).toBe(false);
    expect(useTaskStore.getState().hasMore).toBe(false);
  });

  it("fetchTasks sets hasMore=true when full page returned", async () => {
    const tasks = Array.from({ length: 100 }, (_, i) =>
      mockTask({ id: `t${i}` }),
    );
    vi.mocked(api.listTasks).mockResolvedValue(tasks);

    await useTaskStore.getState().fetchTasks("p1");

    expect(useTaskStore.getState().hasMore).toBe(true);
  });

  it("fetchMoreTasks appends results", async () => {
    useTaskStore.setState({ tasks: [mockTask({ id: "existing" })] });
    vi.mocked(api.listTasks).mockResolvedValue([mockTask({ id: "new" })]);

    await useTaskStore.getState().fetchMoreTasks("p1");

    expect(api.listTasks).toHaveBeenCalledWith("p1", 100, 1);
    expect(useTaskStore.getState().tasks).toHaveLength(2);
  });

  it("fetchArchivedTasks loads archived tasks", async () => {
    const archived = [mockTask({ id: "a1", archivedAt: "2024-01-01" })];
    vi.mocked(api.listArchivedTasks).mockResolvedValue(archived);

    await useTaskStore.getState().fetchArchivedTasks("p1");

    expect(useTaskStore.getState().archivedTasks).toHaveLength(1);
  });

  it("selectTask sets selectedTaskId", () => {
    useTaskStore.getState().selectTask("t1");
    expect(useTaskStore.getState().selectedTaskId).toBe("t1");
  });

  it("createTask appends task to list", async () => {
    const task = mockTask({ id: "new" });
    vi.mocked(api.createTask).mockResolvedValue(task);

    const result = await useTaskStore
      .getState()
      .createTask("p1", "Title", "Desc", "coder");

    expect(result.id).toBe("new");
    expect(useTaskStore.getState().tasks).toHaveLength(1);
  });

  it("updateTaskStatus uses history for undo support", async () => {
    useTaskStore.setState({ tasks: [mockTask({ id: "t1", status: "queued" })] });
    vi.mocked(api.updateTaskStatus).mockResolvedValue(undefined);

    await useTaskStore.getState().updateTaskStatus("t1", "in_progress");

    expect(api.updateTaskStatus).toHaveBeenCalledWith("t1", "in_progress");
    expect(useTaskStore.getState().tasks[0].status).toBe("in_progress");
    expect(useHistoryStore.getState().canUndo).toBe(true);
  });

  it("updateTask replaces task in list", () => {
    const original = mockTask({ id: "t1", title: "Old" });
    useTaskStore.setState({ tasks: [original] });

    useTaskStore.getState().updateTask({ ...original, title: "New" });

    expect(useTaskStore.getState().tasks[0].title).toBe("New");
  });

  it("toggleSelection adds and removes ids", () => {
    useTaskStore.getState().toggleSelection("t1");
    expect(useTaskStore.getState().selectedIds.has("t1")).toBe(true);

    useTaskStore.getState().toggleSelection("t1");
    expect(useTaskStore.getState().selectedIds.has("t1")).toBe(false);
  });

  it("setSelectionMode clears selection", () => {
    useTaskStore.setState({ selectedIds: new Set(["t1", "t2"]) });

    useTaskStore.getState().setSelectionMode(true);

    expect(useTaskStore.getState().selectionMode).toBe(true);
    expect(useTaskStore.getState().selectedIds.size).toBe(0);
  });

  it("duplicateTask adds duplicated task", async () => {
    const dup = mockTask({ id: "t2", title: "Duplicated" });
    vi.mocked(api.duplicateTask).mockResolvedValue(dup);

    await useTaskStore.getState().duplicateTask("t1");

    expect(useTaskStore.getState().tasks).toHaveLength(1);
    expect(useTaskStore.getState().tasks[0].id).toBe("t2");
  });

  it("batchRetry only retries retryable tasks", async () => {
    useTaskStore.setState({
      tasks: [
        mockTask({ id: "t1", status: "failed" }),
        mockTask({ id: "t2", status: "queued" }),
        mockTask({ id: "t3", status: "needs_revision" }),
      ],
      selectedIds: new Set(["t1", "t2", "t3"]),
    });
    vi.mocked(api.batchRetryTasks).mockResolvedValue(undefined);

    await useTaskStore.getState().batchRetry();

    // Only t1 and t3 are retryable (failed, needs_revision)
    expect(api.batchRetryTasks).toHaveBeenCalledWith(["t1", "t3"]);
    const tasks = useTaskStore.getState().tasks;
    expect(tasks.find((t) => t.id === "t1")?.status).toBe("queued");
    expect(tasks.find((t) => t.id === "t2")?.status).toBe("queued"); // unchanged
    expect(tasks.find((t) => t.id === "t3")?.status).toBe("queued");
  });

  it("batchCancel only cancels queued tasks", async () => {
    useTaskStore.setState({
      tasks: [
        mockTask({ id: "t1", status: "queued" }),
        mockTask({ id: "t2", status: "in_progress" }),
      ],
      selectedIds: new Set(["t1", "t2"]),
    });
    vi.mocked(api.batchCancelTasks).mockResolvedValue(undefined);

    await useTaskStore.getState().batchCancel();

    expect(api.batchCancelTasks).toHaveBeenCalledWith(["t1"]);
    expect(useTaskStore.getState().tasks[0].status).toBe("cancelled");
    expect(useTaskStore.getState().tasks[1].status).toBe("in_progress");
  });
});
