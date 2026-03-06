import { describe, it, expect, vi, beforeEach } from "vitest";
import { useAssetStore } from "../store/assetStore";
import type { GeneratedAsset } from "../types/models";

vi.mock("../tauri", () => ({
  listAssets: vi.fn(),
  approveAsset: vi.fn(),
  deleteAsset: vi.fn(),
}));

import * as api from "../tauri";

const mockAsset = (overrides: Partial<GeneratedAsset> = {}): GeneratedAsset => ({
  id: "a1",
  projectId: "p1",
  taskId: "t1",
  agentType: "imageGenerator",
  assetType: "image",
  name: "test-image.png",
  description: "A test image",
  filePath: "/tmp/test.png",
  mimeType: "image/png",
  fileSize: 1024,
  sourceUrl: null,
  metadata: null,
  status: "pending",
  reviewTaskId: null,
  version: 1,
  parentAssetId: null,
  checksum: null,
  thumbnailPath: null,
  createdAt: "2024-01-01T00:00:00Z",
  updatedAt: "2024-01-01T00:00:00Z",
  ...overrides,
});

describe("assetStore", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useAssetStore.setState({
      assets: [],
      loading: false,
      selectedAssetId: null,
      typeFilter: "all",
      sortField: "date",
      searchQuery: "",
      hasMore: true,
      pageSize: 50,
    });
  });

  it("fetchAssets loads assets", async () => {
    vi.mocked(api.listAssets).mockResolvedValue([mockAsset()]);

    await useAssetStore.getState().fetchAssets("p1");

    expect(api.listAssets).toHaveBeenCalledWith("p1", 50, 0);
    expect(useAssetStore.getState().assets).toHaveLength(1);
    expect(useAssetStore.getState().loading).toBe(false);
  });

  it("fetchMoreAssets appends results", async () => {
    useAssetStore.setState({ assets: [mockAsset({ id: "a1" })] });
    vi.mocked(api.listAssets).mockResolvedValue([mockAsset({ id: "a2" })]);

    await useAssetStore.getState().fetchMoreAssets("p1");

    expect(api.listAssets).toHaveBeenCalledWith("p1", 50, 1);
    expect(useAssetStore.getState().assets).toHaveLength(2);
  });

  it("approveAsset updates status", async () => {
    useAssetStore.setState({ assets: [mockAsset({ id: "a1", status: "pending" })] });
    vi.mocked(api.approveAsset).mockResolvedValue(undefined);

    await useAssetStore.getState().approveAsset("a1");

    expect(api.approveAsset).toHaveBeenCalledWith("a1", true);
    expect(useAssetStore.getState().assets[0].status).toBe("approved");
  });

  it("rejectAsset updates status", async () => {
    useAssetStore.setState({ assets: [mockAsset({ id: "a1", status: "pending" })] });
    vi.mocked(api.approveAsset).mockResolvedValue(undefined);

    await useAssetStore.getState().rejectAsset("a1");

    expect(api.approveAsset).toHaveBeenCalledWith("a1", false);
    expect(useAssetStore.getState().assets[0].status).toBe("rejected");
  });

  it("deleteAsset removes from list and clears selection", async () => {
    useAssetStore.setState({
      assets: [mockAsset({ id: "a1" }), mockAsset({ id: "a2" })],
      selectedAssetId: "a1",
    });
    vi.mocked(api.deleteAsset).mockResolvedValue(undefined);

    await useAssetStore.getState().deleteAsset("a1");

    expect(useAssetStore.getState().assets).toHaveLength(1);
    expect(useAssetStore.getState().selectedAssetId).toBeNull();
  });

  it("filteredAssets filters by type", () => {
    useAssetStore.setState({
      assets: [
        mockAsset({ id: "a1", assetType: "image" }),
        mockAsset({ id: "a2", assetType: "video" }),
      ],
      typeFilter: "image",
    });

    const filtered = useAssetStore.getState().filteredAssets();
    expect(filtered).toHaveLength(1);
    expect(filtered[0].id).toBe("a1");
  });

  it("filteredAssets filters by search query", () => {
    useAssetStore.setState({
      assets: [
        mockAsset({ id: "a1", name: "logo.png", description: "Company logo" }),
        mockAsset({ id: "a2", name: "banner.jpg", description: "Hero banner" }),
      ],
      searchQuery: "logo",
    });

    const filtered = useAssetStore.getState().filteredAssets();
    expect(filtered).toHaveLength(1);
    expect(filtered[0].id).toBe("a1");
  });

  it("filteredAssets sorts by name", () => {
    useAssetStore.setState({
      assets: [
        mockAsset({ id: "a1", name: "Zebra" }),
        mockAsset({ id: "a2", name: "Apple" }),
      ],
      sortField: "name",
    });

    const filtered = useAssetStore.getState().filteredAssets();
    expect(filtered[0].name).toBe("Apple");
    expect(filtered[1].name).toBe("Zebra");
  });

  it("filteredAssets sorts by size descending", () => {
    useAssetStore.setState({
      assets: [
        mockAsset({ id: "a1", fileSize: 100 }),
        mockAsset({ id: "a2", fileSize: 500 }),
      ],
      sortField: "size",
    });

    const filtered = useAssetStore.getState().filteredAssets();
    expect(filtered[0].fileSize).toBe(500);
    expect(filtered[1].fileSize).toBe(100);
  });
});
