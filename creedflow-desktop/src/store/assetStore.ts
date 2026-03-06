import { create } from "zustand";
import type { GeneratedAsset } from "../types/models";
import { showErrorToast } from "../hooks/useErrorToast";
import * as api from "../tauri";

type AssetTypeFilter = "all" | "image" | "video" | "audio" | "design" | "document";
type SortField = "date" | "name" | "type" | "size";

interface AssetStore {
  assets: GeneratedAsset[];
  loading: boolean;
  selectedAssetId: string | null;
  typeFilter: AssetTypeFilter;
  sortField: SortField;
  searchQuery: string;
  hasMore: boolean;
  pageSize: number;

  fetchAssets: (projectId: string) => Promise<void>;
  fetchMoreAssets: (projectId: string) => Promise<void>;
  selectAsset: (id: string | null) => void;
  setTypeFilter: (filter: AssetTypeFilter) => void;
  setSortField: (field: SortField) => void;
  setSearchQuery: (query: string) => void;
  approveAsset: (id: string) => Promise<void>;
  rejectAsset: (id: string) => Promise<void>;
  deleteAsset: (id: string) => Promise<void>;

  // Derived
  filteredAssets: () => GeneratedAsset[];
}

export const useAssetStore = create<AssetStore>((set, get) => ({
  assets: [],
  loading: false,
  selectedAssetId: null,
  typeFilter: "all",
  sortField: "date",
  searchQuery: "",
  hasMore: true,
  pageSize: 50,

  fetchAssets: async (projectId: string) => {
    set({ loading: true });
    try {
      const assets = await api.listAssets(projectId, 50, 0);
      set({ assets, loading: false, hasMore: assets.length >= 50 });
    } catch (e) {
      showErrorToast("Failed to fetch assets", e);
      set({ loading: false });
    }
  },

  fetchMoreAssets: async (projectId: string) => {
    const { assets, pageSize } = get();
    try {
      const more = await api.listAssets(projectId, pageSize, assets.length);
      set((s) => ({
        assets: [...s.assets, ...more],
        hasMore: more.length >= pageSize,
      }));
    } catch (e) {
      showErrorToast("Failed to fetch more assets", e);
    }
  },

  selectAsset: (id) => set({ selectedAssetId: id }),
  setTypeFilter: (filter) => set({ typeFilter: filter }),
  setSortField: (field) => set({ sortField: field }),
  setSearchQuery: (query) => set({ searchQuery: query }),

  approveAsset: async (id: string) => {
    await api.approveAsset(id, true);
    set((s) => ({
      assets: s.assets.map((a) =>
        a.id === id ? { ...a, status: "approved" } : a
      ),
    }));
  },

  rejectAsset: async (id: string) => {
    await api.approveAsset(id, false);
    set((s) => ({
      assets: s.assets.map((a) =>
        a.id === id ? { ...a, status: "rejected" } : a
      ),
    }));
  },

  deleteAsset: async (id: string) => {
    await api.deleteAsset(id);
    set((s) => ({
      assets: s.assets.filter((a) => a.id !== id),
      selectedAssetId: s.selectedAssetId === id ? null : s.selectedAssetId,
    }));
  },

  filteredAssets: () => {
    const { assets, typeFilter, sortField, searchQuery } = get();
    let filtered = [...assets];

    // Type filter
    if (typeFilter !== "all") {
      filtered = filtered.filter((a) => a.assetType === typeFilter);
    }

    // Search
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      filtered = filtered.filter(
        (a) =>
          a.name.toLowerCase().includes(q) ||
          a.description.toLowerCase().includes(q)
      );
    }

    // Sort
    filtered.sort((a, b) => {
      switch (sortField) {
        case "name":
          return a.name.localeCompare(b.name);
        case "type":
          return a.assetType.localeCompare(b.assetType);
        case "size":
          return (b.fileSize ?? 0) - (a.fileSize ?? 0);
        case "date":
        default:
          return b.createdAt.localeCompare(a.createdAt);
      }
    });

    return filtered;
  },
}));
