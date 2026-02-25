import { useEffect } from "react";
import { useTaskStore } from "../../store/taskStore";
import { TaskCard } from "./TaskCard";
import type { TaskStatus } from "../../types/models";

interface Props {
  projectId: string;
}

const COLUMNS: { status: TaskStatus; label: string; color: string }[] = [
  { status: "queued", label: "Queued", color: "border-zinc-600" },
  { status: "in_progress", label: "In Progress", color: "border-blue-500" },
  { status: "passed", label: "Passed", color: "border-green-500" },
  { status: "failed", label: "Failed", color: "border-red-500" },
  { status: "needs_revision", label: "Needs Revision", color: "border-yellow-500" },
];

export function TaskBoard({ projectId }: Props) {
  const { tasks, fetchTasks, selectTask } = useTaskStore();

  useEffect(() => {
    fetchTasks(projectId);
  }, [projectId, fetchTasks]);

  return (
    <div className="flex-1 flex flex-col">
      <div className="px-4 py-3 border-b border-zinc-800">
        <h2 className="text-sm font-semibold text-zinc-200">Task Board</h2>
        <p className="text-xs text-zinc-500 mt-0.5">
          {tasks.length} task{tasks.length !== 1 ? "s" : ""}
        </p>
      </div>

      <div className="flex-1 overflow-x-auto">
        <div className="flex gap-3 p-4 min-w-max h-full">
          {COLUMNS.map(({ status, label, color }) => {
            const columnTasks = tasks.filter((t) => t.status === status);
            return (
              <div
                key={status}
                className={`w-[260px] flex flex-col bg-zinc-900/30 rounded-lg border-t-2 ${color}`}
              >
                <div className="px-3 py-2 flex items-center justify-between">
                  <span className="text-xs font-medium text-zinc-400">
                    {label}
                  </span>
                  <span className="text-[10px] text-zinc-600 bg-zinc-800 px-1.5 py-0.5 rounded">
                    {columnTasks.length}
                  </span>
                </div>
                <div className="flex-1 overflow-y-auto px-2 pb-2 space-y-1.5">
                  {columnTasks.map((task) => (
                    <TaskCard
                      key={task.id}
                      task={task}
                      onClick={() => selectTask(task.id)}
                    />
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
