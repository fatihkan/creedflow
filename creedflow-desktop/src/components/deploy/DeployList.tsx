import { useEffect, useState } from "react";
import { Rocket, Trash2 } from "lucide-react";
import { useProjectStore } from "../../store/projectStore";
import * as api from "../../tauri";
import type { DeploymentInfo } from "../../types/models";

const STATUS_COLORS: Record<string, string> = {
  pending: "bg-zinc-600",
  in_progress: "bg-blue-500",
  success: "bg-green-500",
  failed: "bg-red-500",
  rolled_back: "bg-yellow-500",
};

export function DeployList() {
  const selectedProjectId = useProjectStore((s) => s.selectedProjectId);
  const [deployments, setDeployments] = useState<DeploymentInfo[]>([]);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [selectionMode, setSelectionMode] = useState(false);

  useEffect(() => {
    if (selectedProjectId) {
      api.listDeployments(selectedProjectId).then(setDeployments).catch(console.error);
    }
  }, [selectedProjectId]);

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
    ["success", "failed", "rolled_back"].includes(status);

  if (!selectedProjectId) {
    return (
      <div className="flex-1 flex items-center justify-center text-zinc-500 text-sm">
        Select a project to view deployments
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col">
      <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
        <div>
          <h2 className="text-sm font-semibold text-zinc-200">Deployments</h2>
          <p className="text-xs text-zinc-500 mt-0.5">
            {deployments.length} deployment{deployments.length !== 1 ? "s" : ""}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {selectionMode && selectedIds.size > 0 && (
            <button
              onClick={deleteSelected}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-red-600/20 text-red-400 rounded-md hover:bg-red-600/30"
            >
              <Trash2 className="w-3 h-3" />
              Delete ({selectedIds.size})
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
            {selectionMode ? "Cancel" : "Select"}
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        {deployments.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-zinc-500">
            <Rocket className="w-8 h-8 mb-2 opacity-50" />
            <p className="text-sm">No deployments yet</p>
          </div>
        ) : (
          <div className="p-4 space-y-2">
            {deployments.map((dep) => (
              <div
                key={dep.id}
                onClick={() =>
                  selectionMode && isDeletable(dep.status) && toggleSelection(dep.id)
                }
                className={`p-3 rounded-md border transition-colors ${
                  selectedIds.has(dep.id)
                    ? "bg-red-600/10 border-red-600/30"
                    : "bg-zinc-800/50 border-zinc-800"
                } ${selectionMode && isDeletable(dep.status) ? "cursor-pointer" : ""}`}
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
                      {dep.status}
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
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
