import { useEffect, useState } from "react";
import { useTaskStore } from "../../store/taskStore";
import { AgentTypeBadge } from "../shared/AgentTypeBadge";
import { StatusBadge } from "../shared/StatusBadge";
import { SearchBar } from "../shared/SearchBar";
import { Archive, RotateCcw, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";

export function ArchivedTasksView() {
  const {
    archivedTasks,
    fetchArchivedTasks,
    selectedIds,
    selectionMode,
    setSelectionMode,
    toggleSelection,
    restoreSelected,
    deleteSelected,
    clearSelection,
  } = useTaskStore();

  const { t } = useTranslation();
  const [search, setSearch] = useState("");

  useEffect(() => {
    fetchArchivedTasks();
  }, [fetchArchivedTasks]);

  const filteredTasks = search.trim()
    ? archivedTasks.filter((t) => {
        const q = search.toLowerCase();
        return (
          t.title.toLowerCase().includes(q) ||
          t.agentType.toLowerCase().includes(q)
        );
      })
    : archivedTasks;

  return (
    <div className="flex-1 flex flex-col">
      <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
        <div>
          <h2 className="text-sm font-semibold text-zinc-200">{t("tasks.archived.title")}</h2>
          <p className="text-xs text-zinc-500 mt-0.5">
            {filteredTasks.length !== 1 ? t("tasks.archived.count_plural", { count: filteredTasks.length }) : t("tasks.archived.count", { count: filteredTasks.length })}
            {search && ` ${t("tasks.matching", { search })}`}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <SearchBar
            value={search}
            onChange={setSearch}
            placeholder={t("tasks.archived.searchPlaceholder")}
          />
          {selectionMode && selectedIds.size > 0 && (
            <>
              <button
                onClick={restoreSelected}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-blue-600/20 text-blue-400 rounded-md hover:bg-blue-600/30"
              >
                <RotateCcw className="w-3 h-3" />
                {t("tasks.archived.restore")} ({selectedIds.size})
              </button>
              <button
                onClick={deleteSelected}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-red-600/20 text-red-400 rounded-md hover:bg-red-600/30"
              >
                <Trash2 className="w-3 h-3" />
                {t("tasks.archived.delete")} ({selectedIds.size})
              </button>
            </>
          )}
          <button
            onClick={() =>
              selectionMode ? clearSelection() : setSelectionMode(true)
            }
            className={`px-3 py-1.5 text-xs rounded-md ${
              selectionMode
                ? "bg-zinc-700 text-zinc-200"
                : "bg-zinc-800 text-zinc-400 hover:text-zinc-200"
            }`}
          >
            {selectionMode ? t("common.cancel") : t("tasks.select")}
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        {filteredTasks.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-zinc-500">
            <Archive className="w-8 h-8 mb-2 opacity-50" />
            <p className="text-sm">{search ? t("tasks.archived.noMatch") : t("tasks.archived.empty")}</p>
          </div>
        ) : (
          <div className="p-4 space-y-1">
            {filteredTasks.map((task) => (
              <div
                key={task.id}
                onClick={() => selectionMode && toggleSelection(task.id)}
                className={`flex items-center gap-3 p-3 rounded-md border transition-colors ${
                  selectedIds.has(task.id)
                    ? "bg-brand-600/10 border-brand-600/30"
                    : "bg-zinc-800/50 border-zinc-800 hover:border-zinc-700"
                } ${selectionMode ? "cursor-pointer" : ""}`}
              >
                {selectionMode && (
                  <input
                    type="checkbox"
                    checked={selectedIds.has(task.id)}
                    onChange={() => toggleSelection(task.id)}
                    className="w-4 h-4 rounded border-zinc-600 bg-zinc-800"
                  />
                )}
                <div className="flex-1 min-w-0">
                  <p className="text-xs text-zinc-200 font-medium truncate">
                    {task.title}
                  </p>
                  <div className="flex items-center gap-1.5 mt-1">
                    <AgentTypeBadge agentType={task.agentType} />
                    <StatusBadge status={task.status} />
                    {task.archivedAt && (
                      <span className="text-[10px] text-zinc-600">
                        {t("tasks.archived.archivedDate", { date: new Date(task.archivedAt).toLocaleDateString() })}
                      </span>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
