import { useCallback, useEffect, useState } from "react";
import { Sidebar, type SidebarSection } from "./components/layout/Sidebar";
import { ContentArea } from "./components/layout/ContentArea";
import { DetailPanel } from "./components/layout/DetailPanel";
import { ProjectDetailPanel } from "./components/projects/ProjectDetailPanel";
import { SetupWizard } from "./components/setup/SetupWizard";
import { useProjectStore } from "./store/projectStore";
import { useTaskStore } from "./store/taskStore";
import { useSettingsStore } from "./store/settingsStore";
import { useTauriEvent } from "./hooks/useTauriEvent";

type DetailMode = "none" | "task" | "project";

function App() {
  const [section, setSection] = useState<SidebarSection>("projects");
  const [detailMode, setDetailMode] = useState<DetailMode>("none");
  const selectedProjectId = useProjectStore((s) => s.selectedProjectId);
  const selectedTaskId = useTaskStore((s) => s.selectedTaskId);
  const selectTask = useTaskStore((s) => s.selectTask);
  const updateTask = useTaskStore((s) => s.updateTask);
  const settings = useSettingsStore((s) => s.settings);
  const fetchSettings = useSettingsStore((s) => s.fetchSettings);

  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  // Show project detail when a project is selected from the projects list
  useEffect(() => {
    if (selectedProjectId && section === "projects") {
      setDetailMode("project");
    }
  }, [selectedProjectId, section]);

  // Show task detail when a task is selected
  useEffect(() => {
    if (selectedTaskId) {
      setDetailMode("task");
    }
  }, [selectedTaskId]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey) {
        const sections: SidebarSection[] = [
          "projects",
          "tasks",
          "agents",
          "reviews",
          "deploys",
          "prompts",
          "assets",
          "gitHistory",
        ];
        const num = parseInt(e.key);
        if (num >= 1 && num <= sections.length) {
          e.preventDefault();
          setSection(sections[num - 1]);
        }
      }
      if (e.key === "Escape") {
        setDetailMode("none");
        selectTask(null);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [selectTask]);

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

  const closeDetail = () => {
    setDetailMode("none");
    selectTask(null);
  };

  const handleViewTasks = () => {
    setSection("tasks");
    setDetailMode("none");
  };

  // Show setup wizard if setup is not completed
  if (settings && !settings.hasCompletedSetup) {
    return <SetupWizard />;
  }

  // Wait for settings to load
  if (!settings) {
    return (
      <div className="flex h-screen w-screen items-center justify-center text-zinc-500 text-sm">
        Loading...
      </div>
    );
  }

  return (
    <div className="flex h-screen w-screen overflow-hidden">
      <Sidebar selected={section} onSelect={setSection} />
      <div className="flex-1 flex flex-row min-w-0">
        <div className="flex-1 flex flex-col min-w-0">
          <ContentArea
            section={section}
            selectedProjectId={selectedProjectId}
          />
        </div>
        {detailMode === "task" && (
          <DetailPanel onClose={closeDetail} />
        )}
        {detailMode === "project" && selectedProjectId && (
          <ProjectDetailPanel
            projectId={selectedProjectId}
            onClose={closeDetail}
            onViewTasks={handleViewTasks}
          />
        )}
      </div>
    </div>
  );
}

export default App;
