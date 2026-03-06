import { describe, it, expect, vi, beforeEach } from "vitest";
import { useProjectStore } from "../store/projectStore";
import type { Project } from "../types/models";

// Mock the tauri module
vi.mock("../tauri", () => ({
  listProjects: vi.fn(),
  createProject: vi.fn(),
  deleteProject: vi.fn(),
}));

import * as api from "../tauri";

const mockProject = (overrides: Partial<Project> = {}): Project => ({
  id: "p1",
  name: "Test Project",
  description: "A test project",
  techStack: "React",
  status: "planning",
  directoryPath: "/tmp/test",
  projectType: "software",
  telegramChatId: null,
  stagingPrNumber: null,
  completedAt: null,
  createdAt: "2024-01-01T00:00:00Z",
  updatedAt: "2024-01-01T00:00:00Z",
  ...overrides,
});

describe("projectStore", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useProjectStore.setState({
      projects: [],
      selectedProjectId: null,
      loading: false,
      hasMore: true,
      pageSize: 50,
    });
  });

  it("starts with empty state", () => {
    const state = useProjectStore.getState();
    expect(state.projects).toEqual([]);
    expect(state.selectedProjectId).toBeNull();
    expect(state.loading).toBe(false);
  });

  it("fetchProjects loads projects and sets hasMore", async () => {
    const projects = Array.from({ length: 50 }, (_, i) =>
      mockProject({ id: `p${i}` }),
    );
    vi.mocked(api.listProjects).mockResolvedValue(projects);

    await useProjectStore.getState().fetchProjects();

    const state = useProjectStore.getState();
    expect(state.projects).toHaveLength(50);
    expect(state.hasMore).toBe(true);
    expect(state.loading).toBe(false);
    expect(api.listProjects).toHaveBeenCalledWith(50, 0);
  });

  it("fetchProjects sets hasMore=false when less than page size", async () => {
    vi.mocked(api.listProjects).mockResolvedValue([mockProject()]);

    await useProjectStore.getState().fetchProjects();

    expect(useProjectStore.getState().hasMore).toBe(false);
  });

  it("fetchProjects handles errors gracefully", async () => {
    vi.mocked(api.listProjects).mockRejectedValue(new Error("Network error"));

    await useProjectStore.getState().fetchProjects();

    const state = useProjectStore.getState();
    expect(state.projects).toEqual([]);
    expect(state.loading).toBe(false);
  });

  it("fetchMoreProjects appends to existing list", async () => {
    useProjectStore.setState({ projects: [mockProject({ id: "existing" })] });
    vi.mocked(api.listProjects).mockResolvedValue([mockProject({ id: "new" })]);

    await useProjectStore.getState().fetchMoreProjects();

    const state = useProjectStore.getState();
    expect(state.projects).toHaveLength(2);
    expect(state.projects[0].id).toBe("existing");
    expect(state.projects[1].id).toBe("new");
    expect(api.listProjects).toHaveBeenCalledWith(50, 1);
  });

  it("selectProject sets selectedProjectId", () => {
    useProjectStore.getState().selectProject("p1");
    expect(useProjectStore.getState().selectedProjectId).toBe("p1");

    useProjectStore.getState().selectProject(null);
    expect(useProjectStore.getState().selectedProjectId).toBeNull();
  });

  it("createProject adds project to the front of the list", async () => {
    useProjectStore.setState({ projects: [mockProject({ id: "old" })] });
    const newProject = mockProject({ id: "new", name: "New Project" });
    vi.mocked(api.createProject).mockResolvedValue(newProject);

    const result = await useProjectStore
      .getState()
      .createProject("New Project", "desc", "React", "software");

    expect(result.id).toBe("new");
    const state = useProjectStore.getState();
    expect(state.projects[0].id).toBe("new");
    expect(state.projects[1].id).toBe("old");
  });

  it("deleteProject removes project from list", async () => {
    useProjectStore.setState({
      projects: [mockProject({ id: "p1" }), mockProject({ id: "p2" })],
      selectedProjectId: "p1",
    });
    vi.mocked(api.deleteProject).mockResolvedValue(undefined);

    await useProjectStore.getState().deleteProject("p1");

    const state = useProjectStore.getState();
    expect(state.projects).toHaveLength(1);
    expect(state.projects[0].id).toBe("p2");
    expect(state.selectedProjectId).toBeNull();
  });

  it("deleteProject preserves selectedProjectId if different", async () => {
    useProjectStore.setState({
      projects: [mockProject({ id: "p1" }), mockProject({ id: "p2" })],
      selectedProjectId: "p2",
    });
    vi.mocked(api.deleteProject).mockResolvedValue(undefined);

    await useProjectStore.getState().deleteProject("p1");

    expect(useProjectStore.getState().selectedProjectId).toBe("p2");
  });
});
