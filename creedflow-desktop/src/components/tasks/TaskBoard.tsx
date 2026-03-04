import { useEffect, useState } from "react";
import { useTaskStore } from "../../store/taskStore";
import { TaskCard } from "./TaskCard";
import { Archive, RotateCcw, XCircle, MessageCircle, CheckSquare, Square } from "lucide-react";
import { SearchBar } from "../shared/SearchBar";
import { SkeletonCard } from "../shared/Skeleton";
import type { AgentTask, TaskStatus } from "../../types/models";

interface Props {
  projectId: string;
  onToggleChat?: (projectId: string) => void;
  showChatPanel?: boolean;
}

const COLUMNS: { status: TaskStatus; label: string; color: string }[] = [
  { status: "queued", label: "Queued", color: "border-zinc-600" },
  { status: "in_progress", label: "In Progress", color: "border-blue-500" },
  { status: "passed", label: "Passed", color: "border-green-500" },
  { status: "failed", label: "Failed", color: "border-red-500" },
  { status: "needs_revision", label: "Needs Revision", color: "border-yellow-500" },
  { status: "cancelled", label: "Cancelled", color: "border-zinc-500" },
];

const ARCHIVABLE: TaskStatus[] = ["passed", "failed", "cancelled"];
const RETRYABLE: TaskStatus[] = ["failed", "needs_revision", "cancelled"];

const VALID_TRANSITIONS: Record<string, TaskStatus[]> = {
  queued: ["in_progress", "cancelled"],
  in_progress: ["passed", "failed", "needs_revision"],
  passed: [],
  failed: ["queued"],
  needs_revision: ["queued"],
  cancelled: ["queued"],
};

export function TaskBoard({ projectId, onToggleChat, showChatPanel }: Props) {
  const {
    tasks,
    loading,
    fetchTasks,
    selectTask,
    selectionMode,
    setSelectionMode,
    selectedIds,
    toggleSelection,
    archiveSelected,
    clearSelection,
    updateTaskStatus,
    batchRetry,
    batchCancel,
  } = useTaskStore();

  const [search, setSearch] = useState("");

  useEffect(() => {
    fetchTasks(projectId);
  }, [projectId, fetchTasks]);

  const filteredTasks = search.trim()
    ? tasks.filter((t) => {
        const q = search.toLowerCase();
        return (
          t.title.toLowerCase().includes(q) ||
          t.description.toLowerCase().includes(q) ||
          t.agentType.toLowerCase().includes(q) ||
          (t.backend || "").toLowerCase().includes(q)
        );
      })
    : tasks;

  const handleDragStart = (e: React.DragEvent, task: AgentTask) => {
    e.dataTransfer.setData("text/plain", task.id);
    e.dataTransfer.effectAllowed = "move";
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
  };

  const handleDrop = async (e: React.DragEvent, targetStatus: TaskStatus) => {
    e.preventDefault();
    const taskId = e.dataTransfer.getData("text/plain");
    const task = tasks.find((t) => t.id === taskId);
    if (!task) return;
    const allowed = VALID_TRANSITIONS[task.status] || [];
    if (allowed.includes(targetStatus)) {
      await updateTaskStatus(taskId, targetStatus);
    }
  };

  // Compute which batch actions are available based on selected tasks
  const selectedTasks = tasks.filter((t) => selectedIds.has(t.id));
  const hasRetryable = selectedTasks.some((t) => RETRYABLE.includes(t.status));
  const hasCancellable = selectedTasks.some((t) => t.status === "queued");
  const hasArchivable = selectedTasks.some((t) => ARCHIVABLE.includes(t.status));

  const selectAllInColumn = (status: TaskStatus) => {
    const columnTasks = filteredTasks.filter((t) => t.status === status);
    const allSelected = columnTasks.every((t) => selectedIds.has(t.id));
    columnTasks.forEach((t) => {
      if (allSelected) {
        if (selectedIds.has(t.id)) toggleSelection(t.id);
      } else {
        if (!selectedIds.has(t.id)) toggleSelection(t.id);
      }
    });
  };

  return (
    <div className="flex-1 flex flex-col">
      <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold text-zinc-200">Task Board</h2>
          <p className="text-xs text-zinc-500 mt-0.5">
            {filteredTasks.length} task{filteredTasks.length !== 1 ? "s" : ""}
            {search && ` matching "${search}"`}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <SearchBar
            value={search}
            onChange={setSearch}
            placeholder="Search tasks..."
          />

          {onToggleChat && (
            <button
              onClick={() => onToggleChat(projectId)}
              className={`flex items-center gap-1 px-3 py-1.5 text-xs rounded-md transition-colors ${
                showChatPanel
                  ? "bg-amber-500/20 text-amber-400"
                  : "bg-zinc-800 text-zinc-400 hover:text-zinc-200"
              }`}
              title="Toggle project chat"
            >
              <MessageCircle className="w-3.5 h-3.5" />
              Chat
            </button>
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
            aria-label={selectionMode ? "Cancel selection" : "Enter selection mode"}
          >
            {selectionMode ? "Cancel" : "Select"}
          </button>
        </div>
      </div>

      {/* Batch action bar */}
      {selectionMode && selectedIds.size > 0 && (
        <div className="px-4 py-2 border-b border-zinc-800 bg-zinc-900/60 flex items-center gap-2">
          <span className="text-xs text-zinc-400 mr-2">
            {selectedIds.size} selected
          </span>
          {hasRetryable && (
            <button
              onClick={batchRetry}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-blue-600/20 text-blue-400 rounded-md hover:bg-blue-600/30"
            >
              <RotateCcw className="w-3 h-3" />
              Re-queue
            </button>
          )}
          {hasCancellable && (
            <button
              onClick={batchCancel}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-red-600/20 text-red-400 rounded-md hover:bg-red-600/30"
            >
              <XCircle className="w-3 h-3" />
              Cancel
            </button>
          )}
          {hasArchivable && (
            <button
              onClick={archiveSelected}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-zinc-700 text-zinc-200 rounded-md hover:bg-zinc-600"
            >
              <Archive className="w-3 h-3" />
              Archive
            </button>
          )}
        </div>
      )}

      <div className="flex-1 overflow-x-auto">
        <div className="flex gap-3 p-4 min-w-max h-full">
          {COLUMNS.map(({ status, label, color }) => {
            const columnTasks = filteredTasks.filter((t) => t.status === status);
            const allColumnSelected = columnTasks.length > 0 && columnTasks.every((t) => selectedIds.has(t.id));
            return (
              <div
                key={status}
                className={`w-[240px] flex flex-col bg-zinc-900/30 rounded-lg border-t-2 ${color}`}
                onDragOver={handleDragOver}
                onDrop={(e) => handleDrop(e, status)}
              >
                <div className="px-3 py-2 flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    {selectionMode && columnTasks.length > 0 && (
                      <button
                        onClick={() => selectAllInColumn(status)}
                        className="text-zinc-500 hover:text-zinc-300"
                        title={allColumnSelected ? "Deselect all" : "Select all"}
                        aria-label={allColumnSelected ? `Deselect all ${label} tasks` : `Select all ${label} tasks`}
                      >
                        {allColumnSelected ? (
                          <CheckSquare className="w-3.5 h-3.5" />
                        ) : (
                          <Square className="w-3.5 h-3.5" />
                        )}
                      </button>
                    )}
                    <span className="text-xs font-medium text-zinc-400">
                      {label}
                    </span>
                  </div>
                  <span className="text-[10px] text-zinc-600 bg-zinc-800 px-1.5 py-0.5 rounded">
                    {columnTasks.length}
                  </span>
                </div>
                <div className="flex-1 overflow-y-auto px-2 pb-2 space-y-1.5">
                  {loading ? (
                    <>
                      <SkeletonCard />
                      <SkeletonCard />
                    </>
                  ) : columnTasks.map((task) => (
                    <div key={task.id} className="relative">
                      {selectionMode && (
                        <div
                          className="absolute inset-0 z-10 flex items-start justify-start p-2 cursor-pointer"
                          onClick={() => toggleSelection(task.id)}
                        >
                          <input
                            type="checkbox"
                            checked={selectedIds.has(task.id)}
                            onChange={() => toggleSelection(task.id)}
                            className="w-4 h-4 rounded border-zinc-600 bg-zinc-800"
                          />
                        </div>
                      )}
                      <div
                        draggable={!selectionMode}
                        onDragStart={(e) => handleDragStart(e, task)}
                        className={
                          selectionMode
                            ? selectedIds.has(task.id)
                              ? "opacity-75"
                              : ""
                            : ""
                        }
                      >
                        <TaskCard
                          task={task}
                          onClick={() =>
                            selectionMode
                              ? toggleSelection(task.id)
                              : selectTask(task.id)
                          }
                        />
                      </div>
                    </div>
                  ))}
                </div>

              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
