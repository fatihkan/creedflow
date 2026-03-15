import { useEffect, useState } from "react";
import appLogo from "../../assets/logo-32.png";
import {
  FolderKanban,
  LayoutDashboard,
  Bot,
  FileCheck,
  Rocket,
  Settings,
  BookOpen,
  Archive,
  GitBranch,
  GitCompareArrows,
  Package,
  Github,
  ChevronDown,
  ChevronRight,
  Circle,
  Bell,
  Radio,
  Workflow,
} from "lucide-react";
import { useProjectStore } from "../../store/projectStore";
import { useTaskStore } from "../../store/taskStore";
import { useReviewStore } from "../../store/reviewStore";
import { useNotificationStore } from "../../store/notificationStore";
import { NotificationPanel } from "../notifications/NotificationPanel";
import { useTranslation } from "react-i18next";

export type SidebarSection =
  | "projects"
  | "tasks"
  | "agents"
  | "costs"
  | "reviews"
  | "deploys"
  | "settings"
  | "prompts"
  | "archive"
  | "gitHistory"
  | "assets"
  | "publishing"
  | "automation"
  | "compare";

interface SidebarProps {
  selected: SidebarSection;
  onSelect: (section: SidebarSection) => void;
}

const STATUS_COLORS: Record<string, string> = {
  completed: "bg-green-500",
  in_progress: "bg-blue-500",
  analyzing: "bg-amber-500",
  deploying: "bg-purple-500",
  reviewing: "bg-cyan-500",
  failed: "bg-red-500",
  paused: "bg-zinc-500",
  planning: "bg-zinc-400",
};

export function Sidebar({ selected, onSelect }: SidebarProps) {
  const { t } = useTranslation();
  const projects = useProjectStore((s) => s.projects);
  const fetchProjects = useProjectStore((s) => s.fetchProjects);
  const selectedProjectId = useProjectStore((s) => s.selectedProjectId);
  const selectProject = useProjectStore((s) => s.selectProject);

  const archivedCount = useTaskStore((s) => s.archivedTasks.length);
  const fetchArchivedTasks = useTaskStore((s) => s.fetchArchivedTasks);
  const activeTasks = useTaskStore((s) => s.tasks.filter((t) => t.status === "in_progress").length);

  const pendingReviewCount = useReviewStore((s) => s.pendingCount);
  const fetchPendingCount = useReviewStore((s) => s.fetchPendingCount);

  const unreadNotifCount = useNotificationStore((s) => s.unreadCount);
  const showNotifPanel = useNotificationStore((s) => s.showPanel);
  const setShowNotifPanel = useNotificationStore((s) => s.setShowPanel);

  const [expandedSections, setExpandedSections] = useState<Record<string, boolean>>({
    workspace: true,
    recent: true,
    pipeline: true,
    monitor: true,
    library: true,
  });

  useEffect(() => {
    fetchProjects();
    fetchArchivedTasks();
    fetchPendingCount();
  }, [fetchProjects, fetchArchivedTasks, fetchPendingCount]);

  const toggleSection = (id: string) => {
    setExpandedSections((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  const recentProjects = [...projects]
    .sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime())
    .slice(0, 5);

  return (
    <aside className="w-[220px] min-w-[180px] max-w-[280px] bg-zinc-900/50 border-r border-zinc-800 flex flex-col">
      {/* Brand header */}
      <div className="h-12 flex items-center gap-2.5 px-4 border-b border-zinc-800">
        <img src={appLogo} alt="CreedFlow" className="w-6 h-6 rounded" />
        <div>
          <h1 className="text-xs font-bold text-brand-400 tracking-wider leading-none">
            {t("app.name")}
          </h1>
          <p className="text-[9px] text-zinc-600 leading-none mt-0.5">{t("app.tagline")}</p>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 py-1.5 overflow-y-auto" aria-label="Main navigation">
        {/* ─── Workspace ─── */}
        <SectionHeader
          label={t("sidebar.workspace")}
          expanded={expandedSections.workspace}
          onToggle={() => toggleSection("workspace")}
        />
        {expandedSections.workspace && (
          <div className="px-2 space-y-0.5 mb-1">
            <NavItem id="projects" label={t("sidebar.projects")} icon={FolderKanban} selected={selected} onSelect={onSelect} />
            <NavItem id="tasks" label={t("sidebar.tasks")} icon={LayoutDashboard} selected={selected} onSelect={onSelect} badge={activeTasks > 0 ? activeTasks : undefined} badgeColor="bg-blue-500/20 text-blue-400" />
            <NavItem id="archive" label={t("sidebar.archive")} icon={Archive} selected={selected} onSelect={onSelect} badge={archivedCount > 0 ? archivedCount : undefined} />
          </div>
        )}

        {/* ─── Recent Projects ─── */}
        {recentProjects.length > 0 && (
          <>
            <SectionHeader
              label={t("sidebar.recent")}
              expanded={expandedSections.recent}
              onToggle={() => toggleSection("recent")}
            />
            {expandedSections.recent && (
              <div className="px-2 space-y-0.5 mb-1">
                {recentProjects.map((project) => (
                  <button
                    key={project.id}
                    onClick={() => {
                      selectProject(project.id);
                      onSelect("tasks");
                    }}
                    className={`w-full flex items-center gap-2 px-3 py-1.5 rounded-md text-xs transition-colors ${
                      selectedProjectId === project.id
                        ? "bg-brand-600/15 text-brand-400"
                        : "text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800/50"
                    }`}
                  >
                    <Circle className={`w-2 h-2 flex-shrink-0 fill-current ${
                      STATUS_COLORS[project.status] ? STATUS_COLORS[project.status].replace("bg-", "text-") : "text-zinc-600"
                    }`} />
                    <span className="truncate">{project.name}</span>
                  </button>
                ))}
                {projects.length > 5 && (
                  <button
                    onClick={() => onSelect("projects")}
                    className="w-full px-3 py-1 text-[10px] text-zinc-600 hover:text-zinc-400 text-left"
                  >
                    {t("sidebar.viewAll", { count: projects.length })}
                  </button>
                )}
              </div>
            )}
          </>
        )}

        {/* ─── Pipeline ─── */}
        <SectionHeader
          label={t("sidebar.pipeline")}
          expanded={expandedSections.pipeline}
          onToggle={() => toggleSection("pipeline")}
        />
        {expandedSections.pipeline && (
          <div className="px-2 space-y-0.5 mb-1">
            <NavItem id="gitHistory" label={t("sidebar.gitHistory")} icon={GitBranch} selected={selected} onSelect={onSelect} />
            <NavItem id="deploys" label={t("sidebar.deployments")} icon={Rocket} selected={selected} onSelect={onSelect} />
            <NavItem id="publishing" label={t("sidebar.publishing")} icon={Radio} selected={selected} onSelect={onSelect} />
            <NavItem id="automation" label="Automation" icon={Workflow} selected={selected} onSelect={onSelect} />
          </div>
        )}

        {/* ─── Monitor ─── */}
        <SectionHeader
          label={t("sidebar.monitor")}
          expanded={expandedSections.monitor}
          onToggle={() => toggleSection("monitor")}
        />
        {expandedSections.monitor && (
          <div className="px-2 space-y-0.5 mb-1">
            <NavItem id="agents" label={t("sidebar.agents")} icon={Bot} selected={selected} onSelect={onSelect} />
            <NavItem id="reviews" label={t("sidebar.reviews")} icon={FileCheck} selected={selected} onSelect={onSelect} badge={pendingReviewCount > 0 ? pendingReviewCount : undefined} badgeColor="bg-amber-500/20 text-amber-400" />
            <NavItem id="compare" label={t("sidebar.compare")} icon={GitCompareArrows} selected={selected} onSelect={onSelect} />
          </div>
        )}

        {/* ─── Library ─── */}
        <SectionHeader
          label={t("sidebar.library")}
          expanded={expandedSections.library}
          onToggle={() => toggleSection("library")}
        />
        {expandedSections.library && (
          <div className="px-2 space-y-0.5 mb-1">
            <NavItem id="prompts" label={t("sidebar.prompts")} icon={BookOpen} selected={selected} onSelect={onSelect} />
            <NavItem id="assets" label={t("sidebar.assets")} icon={Package} selected={selected} onSelect={onSelect} />
          </div>
        )}
      </nav>

      {/* Bottom bar */}
      <div className="border-t border-zinc-800 p-2 space-y-1">
        {/* Notifications */}
        <div className="relative">
          <button
            onClick={() => setShowNotifPanel(!showNotifPanel)}
            className="w-full flex items-center gap-2.5 px-3 py-1.5 rounded-md text-xs text-zinc-400 hover:text-zinc-200 hover:bg-zinc-800/50 transition-colors"
            aria-label={`Notifications${unreadNotifCount > 0 ? `, ${unreadNotifCount} unread` : ""}`}
          >
            <div className="relative">
              <Bell className="w-4 h-4 flex-shrink-0" />
              {unreadNotifCount > 0 && (
                <span className="absolute -top-1 -right-1.5 text-[8px] font-bold text-white bg-red-500 rounded-full w-3.5 h-3.5 flex items-center justify-center leading-none">
                  {Math.min(unreadNotifCount, 9)}
                </span>
              )}
            </div>
            <span className="flex-1 text-left">{t("sidebar.notifications")}</span>
            {unreadNotifCount > 0 && (
              <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-red-500/20 text-red-400">
                {unreadNotifCount}
              </span>
            )}
          </button>
          {showNotifPanel && (
            <div className="absolute bottom-full left-0 mb-2 z-50">
              <NotificationPanel onClose={() => setShowNotifPanel(false)} />
            </div>
          )}
        </div>

        {/* Settings */}
        <NavItem id="settings" label={t("sidebar.settings")} icon={Settings} selected={selected} onSelect={onSelect} />

        {/* GitHub */}
        <button
          onClick={() => window.open("https://github.com/fatihkan/creedflow", "_blank")}
          className="w-full flex items-center gap-2.5 px-3 py-1.5 rounded-md text-xs text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800/50 transition-colors"
        >
          <Github className="w-4 h-4 flex-shrink-0" />
          <span>{t("sidebar.github")}</span>
        </button>
      </div>
    </aside>
  );
}

/* ─── Sub-components ─── */

function SectionHeader({
  label,
  expanded,
  onToggle,
}: {
  label: string;
  expanded: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      onClick={onToggle}
      className="w-full flex items-center gap-1 px-4 py-1.5 text-[10px] font-semibold text-zinc-600 uppercase tracking-wider hover:text-zinc-400 transition-colors"
      aria-expanded={expanded}
      aria-label={`${label} section`}
    >
      {expanded ? (
        <ChevronDown className="w-3 h-3" />
      ) : (
        <ChevronRight className="w-3 h-3" />
      )}
      {label}
    </button>
  );
}

function NavItem({
  id,
  label,
  icon: Icon,
  selected,
  onSelect,
  badge,
  badgeColor,
}: {
  id: SidebarSection;
  label: string;
  icon: React.FC<{ className?: string }>;
  selected: SidebarSection;
  onSelect: (section: SidebarSection) => void;
  badge?: number;
  badgeColor?: string;
}) {
  return (
    <button
      onClick={() => onSelect(id)}
      aria-label={label}
      aria-current={selected === id ? "page" : undefined}
      className={`w-full flex items-center gap-2.5 px-3 py-1.5 rounded-md text-xs transition-colors ${
        selected === id
          ? "bg-brand-600/20 text-brand-400"
          : "text-zinc-400 hover:text-zinc-200 hover:bg-zinc-800/50"
      }`}
    >
      <Icon className="w-4 h-4 flex-shrink-0" />
      <span className="flex-1 text-left">{label}</span>
      {badge != null && (
        <span className={`text-[10px] px-1.5 py-0.5 rounded-full ${badgeColor || "bg-zinc-800 text-zinc-400"}`}>
          {badge}
        </span>
      )}
    </button>
  );
}
