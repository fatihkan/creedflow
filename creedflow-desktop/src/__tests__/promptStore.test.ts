import { describe, it, expect, vi, beforeEach } from "vitest";
import { usePromptStore } from "../store/promptStore";
import type { Prompt } from "../store/promptStore";
import { invoke } from "@tauri-apps/api/core";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

const mockPrompt = (overrides: Partial<Prompt> = {}): Prompt => ({
  id: "pr1",
  title: "Test Prompt",
  content: "Hello, world!",
  source: "user",
  category: "general",
  contributor: null,
  isBuiltIn: false,
  isFavorite: false,
  version: 1,
  createdAt: "2024-01-01T00:00:00Z",
  updatedAt: "2024-01-01T00:00:00Z",
  ...overrides,
});

describe("promptStore", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    usePromptStore.setState({
      prompts: [],
      loading: false,
      hasMore: true,
      pageSize: 50,
      filter: {
        category: null,
        source: null,
        search: "",
        favoritesOnly: false,
      },
    });
  });

  it("starts with empty state", () => {
    const state = usePromptStore.getState();
    expect(state.prompts).toEqual([]);
    expect(state.loading).toBe(false);
  });

  it("fetchPrompts loads prompts", async () => {
    vi.mocked(invoke).mockResolvedValue([mockPrompt()]);

    await usePromptStore.getState().fetchPrompts();

    expect(invoke).toHaveBeenCalledWith("list_prompts", { limit: 50, offset: 0 });
    expect(usePromptStore.getState().prompts).toHaveLength(1);
    expect(usePromptStore.getState().loading).toBe(false);
  });

  it("fetchMorePrompts appends results", async () => {
    usePromptStore.setState({ prompts: [mockPrompt({ id: "pr1" })] });
    vi.mocked(invoke).mockResolvedValue([mockPrompt({ id: "pr2" })]);

    await usePromptStore.getState().fetchMorePrompts();

    expect(invoke).toHaveBeenCalledWith("list_prompts", { limit: 50, offset: 1 });
    expect(usePromptStore.getState().prompts).toHaveLength(2);
  });

  it("createPrompt refreshes the list", async () => {
    const prompts = [mockPrompt({ id: "new" })];
    vi.mocked(invoke).mockResolvedValueOnce(undefined); // create
    vi.mocked(invoke).mockResolvedValueOnce(prompts); // fetch

    await usePromptStore.getState().createPrompt("Title", "Content", "general");

    expect(invoke).toHaveBeenCalledWith("create_prompt", {
      title: "Title",
      content: "Content",
      category: "general",
    });
  });

  it("deletePrompt removes from list", async () => {
    usePromptStore.setState({
      prompts: [mockPrompt({ id: "pr1" }), mockPrompt({ id: "pr2" })],
    });
    vi.mocked(invoke).mockResolvedValue(undefined);

    await usePromptStore.getState().deletePrompt("pr1");

    expect(usePromptStore.getState().prompts).toHaveLength(1);
    expect(usePromptStore.getState().prompts[0].id).toBe("pr2");
  });

  it("toggleFavorite flips isFavorite", async () => {
    usePromptStore.setState({
      prompts: [mockPrompt({ id: "pr1", isFavorite: false })],
    });
    vi.mocked(invoke).mockResolvedValue(undefined);

    await usePromptStore.getState().toggleFavorite("pr1");

    expect(usePromptStore.getState().prompts[0].isFavorite).toBe(true);
  });

  it("setFilter merges filter values", () => {
    usePromptStore.getState().setFilter({ category: "coding" });

    expect(usePromptStore.getState().filter.category).toBe("coding");
    expect(usePromptStore.getState().filter.search).toBe(""); // unchanged
  });

  it("filteredPrompts filters by category", () => {
    usePromptStore.setState({
      prompts: [
        mockPrompt({ id: "pr1", category: "coding" }),
        mockPrompt({ id: "pr2", category: "writing" }),
      ],
      filter: { category: "coding", source: null, search: "", favoritesOnly: false },
    });

    const filtered = usePromptStore.getState().filteredPrompts();
    expect(filtered).toHaveLength(1);
    expect(filtered[0].id).toBe("pr1");
  });

  it("filteredPrompts filters by favorites", () => {
    usePromptStore.setState({
      prompts: [
        mockPrompt({ id: "pr1", isFavorite: true }),
        mockPrompt({ id: "pr2", isFavorite: false }),
      ],
      filter: { category: null, source: null, search: "", favoritesOnly: true },
    });

    const filtered = usePromptStore.getState().filteredPrompts();
    expect(filtered).toHaveLength(1);
    expect(filtered[0].id).toBe("pr1");
  });

  it("filteredPrompts filters by search text", () => {
    usePromptStore.setState({
      prompts: [
        mockPrompt({ id: "pr1", title: "React hooks", content: "useState tutorial" }),
        mockPrompt({ id: "pr2", title: "Python basics", content: "print hello" }),
      ],
      filter: { category: null, source: null, search: "react", favoritesOnly: false },
    });

    const filtered = usePromptStore.getState().filteredPrompts();
    expect(filtered).toHaveLength(1);
    expect(filtered[0].id).toBe("pr1");
  });
});
