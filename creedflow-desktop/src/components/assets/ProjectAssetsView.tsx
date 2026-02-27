import { useEffect } from "react";
import {
  Image,
  Video,
  Music,
  Palette,
  FileText,
  Search,
  ArrowUpDown,
  Package,
} from "lucide-react";
import { useProjectStore } from "../../store/projectStore";
import { useAssetStore } from "../../store/assetStore";
import { AssetCard } from "./AssetCard";
import { AssetDetailSheet } from "./AssetDetailSheet";

const TYPE_FILTERS = [
  { id: "all" as const, label: "All", icon: Package },
  { id: "image" as const, label: "Images", icon: Image },
  { id: "video" as const, label: "Videos", icon: Video },
  { id: "audio" as const, label: "Audio", icon: Music },
  { id: "design" as const, label: "Design", icon: Palette },
  { id: "document" as const, label: "Docs", icon: FileText },
];

const SORT_OPTIONS = [
  { id: "date" as const, label: "Date" },
  { id: "name" as const, label: "Name" },
  { id: "type" as const, label: "Type" },
  { id: "size" as const, label: "Size" },
];

export function ProjectAssetsView() {
  const selectedProjectId = useProjectStore((s) => s.selectedProjectId);
  const {
    loading,
    selectedAssetId,
    typeFilter,
    sortField,
    searchQuery,
    fetchAssets,
    selectAsset,
    setTypeFilter,
    setSortField,
    setSearchQuery,
    filteredAssets,
    assets,
  } = useAssetStore();

  useEffect(() => {
    if (selectedProjectId) {
      fetchAssets(selectedProjectId);
    }
  }, [selectedProjectId, fetchAssets]);

  const filtered = filteredAssets();
  const selectedAsset = assets.find((a) => a.id === selectedAssetId);

  if (!selectedProjectId) {
    return (
      <div className="flex-1 flex items-center justify-center text-zinc-500 text-sm">
        Select a project to view assets
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col">
      {/* Header */}
      <div className="px-4 py-3 border-b border-zinc-800">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-sm font-semibold text-zinc-200">
            Assets
            {assets.length > 0 && (
              <span className="ml-2 text-zinc-500 font-normal">
                {filtered.length}
                {filtered.length !== assets.length && ` / ${assets.length}`}
              </span>
            )}
          </h2>
        </div>

        {/* Toolbar */}
        <div className="flex items-center gap-3">
          {/* Search */}
          <div className="relative flex-1 max-w-[240px]">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-zinc-500" />
            <input
              type="text"
              placeholder="Search assets..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-8 pr-3 py-1.5 bg-zinc-800/60 border border-zinc-700 rounded-md text-xs text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:border-brand-500/50"
            />
          </div>

          {/* Type filter pills */}
          <div className="flex items-center gap-1">
            {TYPE_FILTERS.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                onClick={() => setTypeFilter(id)}
                className={`flex items-center gap-1 px-2 py-1 rounded-md text-[11px] transition-colors ${
                  typeFilter === id
                    ? "bg-brand-600/20 text-brand-400"
                    : "text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800/50"
                }`}
              >
                <Icon className="w-3 h-3" />
                {label}
              </button>
            ))}
          </div>

          {/* Sort */}
          <div className="flex items-center gap-1 ml-auto">
            <ArrowUpDown className="w-3 h-3 text-zinc-500" />
            <select
              value={sortField}
              onChange={(e) => setSortField(e.target.value as typeof sortField)}
              className="bg-transparent text-[11px] text-zinc-400 border-none focus:outline-none cursor-pointer"
            >
              {SORT_OPTIONS.map(({ id, label }) => (
                <option key={id} value={id}>
                  {label}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Grid */}
      <div className="flex-1 overflow-y-auto p-4">
        {loading ? (
          <div className="flex items-center justify-center h-32 text-zinc-500 text-sm">
            Loading assets...
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-48 text-zinc-500">
            <Package className="w-8 h-8 mb-2 opacity-40" />
            <p className="text-sm">
              {assets.length === 0
                ? "No assets generated yet"
                : "No assets match filters"}
            </p>
            <p className="text-xs mt-1 text-zinc-600">
              {assets.length === 0
                ? "Creative agents will produce assets here"
                : "Try adjusting your search or filters"}
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
            {filtered.map((asset) => (
              <AssetCard
                key={asset.id}
                asset={asset}
                selected={asset.id === selectedAssetId}
                onClick={() => selectAsset(asset.id)}
              />
            ))}
          </div>
        )}
      </div>

      {/* Detail sheet */}
      {selectedAsset && (
        <AssetDetailSheet
          asset={selectedAsset}
          onClose={() => selectAsset(null)}
        />
      )}
    </div>
  );
}
