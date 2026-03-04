import { useCallback, useEffect, useState } from "react";
import { Sidebar, type SidebarSection } from "./components/layout/Sidebar";
import { ContentArea } from "./components/layout/ContentArea";
import { DetailPanel } from "./components/layout/DetailPanel";
import { ProjectDetailPanel } from "./components/projects/ProjectDetailPanel";
import { ProjectChatPanel } from "./components/chat/ProjectChatPanel";
import { SetupWizard } from "./components/setup/SetupWizard";
import { ToastOverlay } from "./components/notifications/ToastOverlay";
import { KeyboardShortcutsOverlay } from "./components/shared/KeyboardShortcutsOverlay";
import { ErrorBoundary } from "./components/shared/ErrorBoundary";
import { UpdateBanner } from "./components/shared/UpdateBanner";
import { useProjectStore } from "./store/projectStore";
import { useTaskStore } from "./store/taskStore";
import { useSettingsStore } from "./store/settingsStore";
import { useNotificationStore } from "./store/notificationStore";
import { useThemeStore } from "./store/themeStore";
import { useFontStore } from "./store/fontStore";
import { useTauriEvent } from "./hooks/useTauriEvent";
import * as api from "./tauri";
import type { UpdateInfo } from "./tauri";

type DetailMode = "none" | "task" | "project";

function App() {
  const [section, setSection] = useState<SidebarSection>("projects");
  const [detailMode, setDetailMode] = useState<DetailMode>("none");
  const [showChatPanel, setShowChatPanel] = useState(false);
  const [chatProjectId, setChatProjectId] = useState<string | null>(null);
  const [showShortcuts, setShowShortcuts] = useState(false);
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const selectedProjectId = useProjectStore((s) => s.selectedProjectId);
  const projects = useProjectStore((s) => s.projects);
  const selectedTaskId = useTaskStore((s) => s.selectedTaskId);
  const selectTask = useTaskStore((s) => s.selectTask);
  const updateTask = useTaskStore((s) => s.updateTask);
  const settings = useSettingsStore((s) => s.settings);
  const fetchSettings = useSettingsStore((s) => s.fetchSettings);
  const fetchUnreadCount = useNotificationStore((s) => s.fetchUnreadCount);
  const addToast = useNotificationStore((s) => s.addToast);
  // Initialize theme on mount (store constructor applies the class)
  useThemeStore();
  const initFont = useFontStore((s) => s.initialize);
  useEffect(() => { initFont(); }, [initFont]);

  useEffect(() => {
    fetchSettings();
    fetchUnreadCount();

    // Check for updates
    const dismissedVersion = localStorage.getItem("creedflow_dismissed_update");
    api.checkForUpdates()
      .then((info) => {
        if (info && info.latestVersion !== dismissedVersion) {
          setUpdateInfo(info);
        }
      })
      .catch(() => {/* fail silently */});

    // Poll for unread count every 10s
    const interval = setInterval(() => {
      fetchUnreadCount();
    }, 10000);

    // Catch unhandled promise rejections
    const handleRejection = (event: PromiseRejectionEvent) => {
      event.preventDefault();
      const message =
        event.reason instanceof Error
          ? event.reason.message
          : String(event.reason);
      addToast({
        id: crypto.randomUUID(),
        category: "system",
        severity: "error",
        title: "Unhandled Error",
        message,
        metadata: null,
        isRead: false,
        isDismissed: false,
        createdAt: new Date().toISOString(),
      });
    };
    window.addEventListener("unhandledrejection", handleRejection);

    return () => {
      clearInterval(interval);
      window.removeEventListener("unhandledrejection", handleRejection);
    };
  }, [fetchSettings, fetchUnreadCount, addToast]);

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
      // Cmd+? (Cmd+Shift+/) — keyboard shortcuts overlay
      if ((e.metaKey || e.ctrlKey) && e.key === "?") {
        e.preventDefault();
        setShowShortcuts((v) => !v);
        return;
      }
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
        if (showChatPanel) {
          setShowChatPanel(false);
          return;
        }
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

  // Listen for notification events
  const handleNotificationEvent = useCallback(
    (payload: { id: string; category: string; severity: string; title: string; message: string; createdAt: string }) => {
      addToast({
        id: payload.id,
        category: payload.category as import("./types/models").NotificationCategory,
        severity: payload.severity as import("./types/models").NotificationSeverity,
        title: payload.title,
        message: payload.message,
        metadata: null,
        isRead: false,
        isDismissed: false,
        createdAt: payload.createdAt,
      });
      fetchUnreadCount();
    },
    [addToast, fetchUnreadCount],
  );

  useTauriEvent("app-notification", handleNotificationEvent);

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

  const chatProject = chatProjectId
    ? projects.find((p) => p.id === chatProjectId)
    : null;

  const handleToggleChat = (projectId: string) => {
    if (showChatPanel && chatProjectId === projectId) {
      setShowChatPanel(false);
    } else {
      setChatProjectId(projectId);
      setShowChatPanel(true);
    }
  };

  const handleDismissUpdate = () => {
    if (updateInfo) {
      localStorage.setItem("creedflow_dismissed_update", updateInfo.latestVersion);
    }
    setUpdateInfo(null);
  };

  const handleViewRelease = () => {
    if (updateInfo) {
      api.openUrl(updateInfo.releaseUrl).catch(console.error);
    }
  };

  return (
    <ErrorBoundary>
      <div className="flex flex-col h-screen w-screen overflow-hidden relative">
        {updateInfo && (
          <UpdateBanner
            update={updateInfo}
            onDismiss={handleDismissUpdate}
            onViewRelease={handleViewRelease}
          />
        )}
        <div className="flex flex-1 min-h-0">
        <ToastOverlay />
        <KeyboardShortcutsOverlay
          open={showShortcuts}
          onClose={() => setShowShortcuts(false)}
        />
        <Sidebar selected={section} onSelect={setSection} />
        <div className="flex-1 flex flex-row min-w-0">
          {/* Left: Chat panel */}
          {showChatPanel && chatProjectId && chatProject && (
            <div className="w-[380px] flex-shrink-0">
              <ProjectChatPanel
                projectId={chatProjectId}
                projectName={chatProject.name}
                onClose={() => setShowChatPanel(false)}
              />
            </div>
          )}

          {/* Center: Content */}
          <div className="flex-1 flex flex-col min-w-0">
            <ContentArea
              section={section}
              selectedProjectId={selectedProjectId}
              onToggleChat={handleToggleChat}
              showChatPanel={showChatPanel}
              chatProjectId={chatProjectId}
            />
          </div>

          {/* Right: Detail panels */}
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
      </div>
    </ErrorBoundary>
  );
}

export default App;
