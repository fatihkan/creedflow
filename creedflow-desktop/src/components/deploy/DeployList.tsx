import { useEffect, useState } from "react";
import { Rocket, Trash2, Plus, Filter } from "lucide-react";
import { useProjectStore } from "../../store/projectStore";
import { SearchBar } from "../shared/SearchBar";
import { SkeletonRow } from "../shared/Skeleton";
import * as api from "../../tauri";
import type { DeploymentInfo } from "../../types/models";
import { DeployDetailPanel } from "./DeployDetailPanel";
import { NewDeployDialog } from "./NewDeployDialog";
import { useTranslation } from "react-i18next";
import { showErrorToast } from "../../hooks/useErrorToast";

const STATUS_COLORS: Record<string, string> = {
  pending: "bg-zinc-600",
  in_progress: "bg-blue-500",
  success: "bg-green-500",
  failed: "bg-red-500",
  rolled_back: "bg-yellow-500",
  cancelled: "bg-amber-500",
};

const ENVIRONMENTS = ["all", "development", "staging", "production"] as const;
const STATUSES = ["all", "pending", "in_progress", "success", "failed", "rolled_back", "cancelled"] as const;

export function DeployList() {
  const { t } = useTranslation();
  const selectedProjectId = useProjectStore((s) => s.selectedProjectId);
  const [deployments, setDeployments] = useState<DeploymentInfo[]>([]);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [selectionMode, setSelectionMode] = useState(false);
  const [detailId, setDetailId] = useState<string | null>(null);
  const [envFilter, setEnvFilter] = useState<string>("all");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [showNewDeploy, setShowNewDeploy] = useState(false);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);

  const fetchDeployments = () => {
    if (selectedProjectId) {
      setLoading(true);
      api.listDeployments(selectedProjectId)
        .then(setDeployments)
        .catch((e) => showErrorToast("Failed to load deployments", e))
        .finally(() => setLoading(false));
    }
  };

  useEffect(() => {
    fetchDeployments();
  }, [selectedProjectId]);

  const filtered = deployments.filter((d) => {
    if (envFilter !== "all" && d.environment !== envFilter) return false;
    if (statusFilter !== "all" && d.status !== statusFilter) return false;
    if (search.trim()) {
      const q = search.toLowerCase();
      return (
        d.version.toLowerCase().includes(q) ||
        d.environment.toLowerCase().includes(q) ||
        d.status.toLowerCase().includes(q) ||
        (d.deployMethod || "").toLowerCase().includes(q)
      );
    }
    return true;
  });

  const toggleSelection = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const deleteSelected = async () => {
    const ids = Array.from(selectedIds);
    await api.deleteDeployments(ids);
    setDeployments((d) => d.filter((dep) => !selectedIds.has(dep.id)));
    setSelectedIds(new Set());
    setSelectionMode(false);
  };

  const isDeletable = (status: string) =>
    ["success", "failed", "rolled_back", "cancelled"].includes(status);

  const detailDeployment = deployments.find((d) => d.id === detailId);

  if (!selectedProjectId) {
    return (
      <div className="flex-1 flex items-center justify-center text-zinc-500 text-sm">
        {t("deploy.selectProject")}
      </div>
    );
  }

  return (
    <div className="flex-1 flex">
      {/* Main list */}
      <div className="flex-1 flex flex-col">
        <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
          <div>
            <h2 className="text-sm font-semibold text-zinc-200">{t("deploy.title")}</h2>
            <p className="text-xs text-zinc-500 mt-0.5">
              {deployments.length !== 1 ? t("deploy.count_plural", { filtered: filtered.length, total: deployments.length }) : t("deploy.count", { filtered: filtered.length, total: deployments.length })}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <SearchBar
              value={search}
              onChange={setSearch}
              placeholder={t("deploy.searchPlaceholder")}
            />
            <button
              onClick={() => setShowNewDeploy(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-700 text-white rounded-md transition-colors"
            >
              <Plus className="w-3 h-3" />
              {t("deploy.newDeploy")}
            </button>
            {selectionMode && selectedIds.size > 0 && (
              <button
                onClick={deleteSelected}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-red-600/20 text-red-400 rounded-md hover:bg-red-600/30"
              >
                <Trash2 className="w-3 h-3" />
                {t("deploy.delete", { count: selectedIds.size })}
              </button>
            )}
            <button
              onClick={() => {
                setSelectionMode(!selectionMode);
                setSelectedIds(new Set());
              }}
              className={`px-3 py-1.5 text-xs rounded-md ${
                selectionMode
                  ? "bg-zinc-700 text-zinc-200"
                  : "bg-zinc-800 text-zinc-400 hover:text-zinc-200"
              }`}
            >
              {selectionMode ? t("deploy.cancel") : t("deploy.select")}
            </button>
          </div>
        </div>

        {/* Filters */}
        <div className="px-4 py-2 border-b border-zinc-800/50 flex items-center gap-3">
          <Filter className="w-3.5 h-3.5 text-zinc-500" />
          <div className="flex gap-1">
            {ENVIRONMENTS.map((env) => (
              <button
                key={env}
                onClick={() => setEnvFilter(env)}
                className={`px-2 py-1 text-[10px] rounded transition-colors capitalize ${
                  envFilter === env
                    ? "bg-brand-600/20 text-brand-400"
                    : "bg-zinc-800 text-zinc-500 hover:text-zinc-300"
                }`}
              >
                {env}
              </button>
            ))}
          </div>
          <div className="w-px h-4 bg-zinc-800" />
          <div className="flex gap-1 flex-wrap">
            {STATUSES.map((s) => (
              <button
                key={s}
                onClick={() => setStatusFilter(s)}
                className={`px-2 py-1 text-[10px] rounded transition-colors capitalize ${
                  statusFilter === s
                    ? "bg-brand-600/20 text-brand-400"
                    : "bg-zinc-800 text-zinc-500 hover:text-zinc-300"
                }`}
              >
                {s.replace("_", " ")}
              </button>
            ))}
          </div>
        </div>

        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="p-4 space-y-2">
              <SkeletonRow />
              <SkeletonRow />
              <SkeletonRow />
            </div>
          ) : filtered.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full text-zinc-500">
              <Rocket className="w-8 h-8 mb-2 opacity-50" />
              <p className="text-sm">{t("deploy.noDeployments")}</p>
            </div>
          ) : (
            <div className="p-4 space-y-2">
              {filtered.map((dep) => {
                const isSelected = detailId === dep.id;
                return (
                  <button
                    key={dep.id}
                    onClick={() => {
                      if (selectionMode && isDeletable(dep.status)) {
                        toggleSelection(dep.id);
                      } else {
                        setDetailId(isSelected ? null : dep.id);
                      }
                    }}
                    className={`w-full text-left p-3 rounded-md border transition-colors ${
                      selectedIds.has(dep.id)
                        ? "bg-red-600/10 border-red-600/30"
                        : isSelected
                          ? "bg-brand-600/10 border-brand-500/30"
                          : "bg-zinc-800/50 border-zinc-800 hover:bg-zinc-800/70"
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        {selectionMode && isDeletable(dep.status) && (
                          <input
                            type="checkbox"
                            checked={selectedIds.has(dep.id)}
                            onChange={() => toggleSelection(dep.id)}
                            className="w-4 h-4 rounded border-zinc-600 bg-zinc-800"
                          />
                        )}
                        <span className="text-xs font-medium text-zinc-200">
                          v{dep.version}
                        </span>
                        <span
                          className={`px-1.5 py-0.5 text-[10px] rounded text-white ${STATUS_COLORS[dep.status] || "bg-zinc-600"}`}
                        >
                          {dep.status.replace("_", " ")}
                        </span>
                        <span className="text-[10px] text-zinc-500 capitalize">
                          {dep.environment}
                        </span>
                      </div>
                      <span className="text-[10px] text-zinc-600">
                        {new Date(dep.createdAt).toLocaleDateString()}
                      </span>
                    </div>
                    {dep.deployMethod && (
                      <p className="text-[10px] text-zinc-500 mt-1">
                        {dep.deployMethod}
                        {dep.port ? ` :${dep.port}` : ""}
                      </p>
                    )}
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </div>

      {/* Detail panel */}
      {detailDeployment && (
        <DeployDetailPanel
          deployment={detailDeployment}
          onClose={() => setDetailId(null)}
          onRefresh={fetchDeployments}
        />
      )}

      {/* New deployment dialog */}
      {showNewDeploy && selectedProjectId && (
        <NewDeployDialog
          projectId={selectedProjectId}
          onClose={() => setShowNewDeploy(false)}
          onCreated={() => {
            setShowNewDeploy(false);
            fetchDeployments();
          }}
        />
      )}
    </div>
  );
}
