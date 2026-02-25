import { useCallback, useEffect, useState } from "react";
import { Sidebar, type SidebarSection } from "./components/layout/Sidebar";
import { ContentArea } from "./components/layout/ContentArea";
import { DetailPanel } from "./components/layout/DetailPanel";
import { useProjectStore } from "./store/projectStore";
import { useTaskStore } from "./store/taskStore";
import { useTauriEvent } from "./hooks/useTauriEvent";

function App() {
  const [section, setSection] = useState<SidebarSection>("projects");
  const [showDetail, setShowDetail] = useState(false);
  const selectedProjectId = useProjectStore((s) => s.selectedProjectId);
  const selectedTaskId = useTaskStore((s) => s.selectedTaskId);
  const updateTask = useTaskStore((s) => s.updateTask);

  // Auto-switch to tasks view when a project is selected
  useEffect(() => {
    if (selectedProjectId && section === "projects") {
      setSection("tasks");
    }
  }, [selectedProjectId, section]);

  // Show detail panel when a task is selected
  useEffect(() => {
    if (selectedTaskId) {
      setShowDetail(true);
    }
  }, [selectedTaskId]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey) {
        const sections: SidebarSection[] = [
          "projects", "tasks", "agents", "costs", "reviews", "deploys", "prompts",
        ];
        const num = parseInt(e.key);
        if (num >= 1 && num <= sections.length) {
          e.preventDefault();
          setSection(sections[num - 1]);
        }
      }
      if (e.key === "Escape") {
        setShowDetail(false);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  // Listen to Tauri events for real-time task updates
  const handleTaskStatusChanged = useCallback(
    (payload: { taskId: string; status: string; agentType: string }) => {
      const tasks = useTaskStore.getState().tasks;
      const task = tasks.find((t) => t.id === payload.taskId);
      if (task) {
        updateTask({
          ...task,
          status: payload.status as typeof task.status,
        });
      }
    },
    [updateTask],
  );

  useTauriEvent("task-status-changed", handleTaskStatusChanged);

  return (
    <div className="flex h-screen w-screen overflow-hidden">
      <Sidebar selected={section} onSelect={setSection} />
      <div className="flex-1 flex flex-col min-w-0">
        <ContentArea section={section} selectedProjectId={selectedProjectId} />
        {showDetail && <DetailPanel onClose={() => setShowDetail(false)} />}
      </div>
    </div>
  );
}

export default App;
