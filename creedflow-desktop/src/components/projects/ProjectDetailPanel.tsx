import { useEffect, useState } from "react";
import {
  X,
  BarChart3,
  CheckCircle2,
  Loader2,
  AlertTriangle,
  Terminal,
  FolderOpen,
  Code2,
  Play,
  GitBranch,
  Download,
} from "lucide-react";
import { save } from "@tauri-apps/plugin-dialog";
import { useProjectStore } from "../../store/projectStore";
import * as api from "../../tauri";
import type { AgentTask, DetectedEditor } from "../../types/models";
import { ProjectTimeStats } from "./ProjectTimeStats";
import { useTranslation } from "react-i18next";

interface ProjectDetailPanelProps {
  projectId: string;
  onClose: () => void;
  onViewTasks: () => void;
}

export function ProjectDetailPanel({ projectId, onClose, onViewTasks }: ProjectDetailPanelProps) {
  const { t } = useTranslation();
  const project = useProjectStore((s) => s.projects.find((p) => p.id === projectId));
  const [tasks, setTasks] = useState<AgentTask[]>([]);
  const [loadingTasks, setLoadingTasks] = useState(true);
  const [currentBranch, setCurrentBranch] = useState<string | null>(null);
  const [editors, setEditors] = useState<DetectedEditor[]>([]);
  const [preferredEditor, setPreferredEditor] = useState<string | null>(null);

  useEffect(() => {
    setLoadingTasks(true);
    api
      .listTasks(projectId)
      .then(setTasks)
      .catch(console.error)
      .finally(() => setLoadingTasks(false));

    api.gitCurrentBranch(projectId).then(setCurrentBranch).catch(() => {});
    api.detectEditors().then(setEditors).catch(() => {});
    api.getPreferredEditor().then(setPreferredEditor).catch(() => {});
  }, [projectId]);

  if (!project) {
    return (
      <div className="w-[400px] min-w-[340px] border-l border-zinc-800 bg-zinc-900/30 flex items-center justify-center text-zinc-500 text-sm">
        {t("projectDetail.notFound")}
      </div>
    );
  }

  const totalTasks = tasks.length;
  const doneTasks = tasks.filter((t) => t.status === "passed").length;
  const activeTasks = tasks.filter((t) => t.status === "in_progress").length;
  const failedTasks = tasks.filter((t) => t.status === "failed").length;

  const getEditorCommand = (): string | null => {
    if (preferredEditor) return preferredEditor;
    if (editors.length > 0) return editors[0].command;
    return null;
  };

  const statusColors: Record<string, string> = {
    completed: "bg-green-500/20 text-green-400",
    in_progress: "bg-blue-500/20 text-blue-400",
    analyzing: "bg-amber-500/20 text-amber-400",
    failed: "bg-red-500/20 text-red-400",
    paused: "bg-zinc-500/20 text-zinc-400",
    planning: "bg-zinc-500/20 text-zinc-400",
    reviewing: "bg-cyan-500/20 text-cyan-400",
    deploying: "bg-purple-500/20 text-purple-400",
  };

  return (
    <div className="w-[400px] min-w-[340px] border-l border-zinc-800 bg-zinc-900/30 flex flex-col overflow-hidden animate-slide-in-right">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <div className="flex items-center gap-2 min-w-0 flex-1">
          <span className={`text-[10px] font-medium px-2 py-0.5 rounded-full capitalize ${statusColors[project.status] || "bg-zinc-700 text-zinc-400"}`}>
            {project.status}
          </span>
          {project.projectType && (
            <span className="text-[10px] text-zinc-500 capitalize">{project.projectType}</span>
          )}
        </div>
        <button
          onClick={onClose}
          className="p-1 text-zinc-500 hover:text-zinc-300 rounded flex-shrink-0"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Name & description */}
        <div>
          <h3 className="text-sm font-semibold text-zinc-200">{project.name}</h3>
          <p className="text-xs text-zinc-400 mt-1 leading-relaxed">{project.description}</p>
          {project.techStack && (
            <p className="text-[10px] text-zinc-600 mt-2 font-mono">{project.techStack}</p>
          )}
        </div>

        {/* Stats cards */}
        <div className="grid grid-cols-2 gap-2">
          <StatCard label={t("projectDetail.total")} value={totalTasks} icon={BarChart3} color="text-zinc-400" />
          <StatCard label={t("projectDetail.done")} value={doneTasks} icon={CheckCircle2} color="text-green-400" />
          <StatCard label={t("projectDetail.active")} value={activeTasks} icon={Loader2} color="text-blue-400" />
          <StatCard label={t("projectDetail.failed")} value={failedTasks} icon={AlertTriangle} color="text-red-400" />
        </div>

        {/* Time stats */}
        {totalTasks > 0 && <ProjectTimeStats projectId={projectId} />}

        {/* Branch info */}
        {currentBranch && (
          <div className="flex items-center gap-2 px-3 py-2 bg-zinc-800/50 rounded-md">
            <GitBranch className="w-3.5 h-3.5 text-zinc-500" />
            <span className="text-xs text-zinc-300 font-mono">{currentBranch}</span>
          </div>
        )}

        {/* Quick actions */}
        <div className="space-y-1.5">
          <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
            {t("projectDetail.actions")}
          </label>
          <div className="flex gap-1.5">
            <button
              onClick={onViewTasks}
              className="flex-1 flex items-center gap-2 px-3 py-2 text-xs bg-brand-600/15 text-brand-400 rounded-md hover:bg-brand-600/25 transition-colors"
            >
              <Play className="w-3.5 h-3.5" />
              {t("projectDetail.viewTaskBoard")}
            </button>
            <button
              onClick={async () => {
                const path = await save({
                  defaultPath: `${project.name}.zip`,
                  filters: [{ name: "ZIP", extensions: ["zip"] }],
                });
                if (path) {
                  api.exportProjectZip(projectId, path).catch(console.error);
                }
              }}
              className="flex items-center gap-1.5 px-3 py-2 text-xs bg-zinc-800 text-zinc-300 rounded-md hover:bg-zinc-700 transition-colors"
            >
              <Download className="w-3.5 h-3.5" />
              ZIP
            </button>
          </div>
          {project.directoryPath && (
            <div className="flex gap-1.5">
              <button
                onClick={() => api.openTerminal(project.directoryPath)}
                className="flex-1 flex items-center gap-1.5 px-3 py-2 text-xs bg-zinc-800 text-zinc-300 rounded-md hover:bg-zinc-700 transition-colors"
              >
                <Terminal className="w-3.5 h-3.5" />
                {t("projectDetail.terminal")}
              </button>
              <button
                onClick={() => api.openInFileManager(project.directoryPath)}
                className="flex-1 flex items-center gap-1.5 px-3 py-2 text-xs bg-zinc-800 text-zinc-300 rounded-md hover:bg-zinc-700 transition-colors"
              >
                <FolderOpen className="w-3.5 h-3.5" />
                {t("projectDetail.finder")}
              </button>
              {getEditorCommand() && (
                <button
                  onClick={() => api.openInEditor(project.directoryPath, getEditorCommand()!)}
                  className="flex-1 flex items-center gap-1.5 px-3 py-2 text-xs bg-zinc-800 text-zinc-300 rounded-md hover:bg-zinc-700 transition-colors"
                >
                  <Code2 className="w-3.5 h-3.5" />
                  {t("projectDetail.editor")}
                </button>
              )}
            </div>
          )}
        </div>

        {/* Recent tasks */}
        {!loadingTasks && tasks.length > 0 && (
          <div>
            <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              {t("projectDetail.recentTasks")}
            </label>
            <div className="mt-2 space-y-1">
              {tasks.slice(0, 8).map((task) => (
                <div
                  key={task.id}
                  className="flex items-center justify-between px-2 py-1.5 bg-zinc-800/30 rounded"
                >
                  <div className="flex items-center gap-2 min-w-0">
                    <StatusDot status={task.status} />
                    <span className="text-xs text-zinc-300 truncate">{task.title}</span>
                  </div>
                  <span className="text-[10px] text-zinc-600 capitalize flex-shrink-0 ml-2">
                    {task.agentType}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function StatCard({
  label,
  value,
  icon: Icon,
  color,
}: {
  label: string;
  value: number;
  icon: React.FC<{ className?: string }>;
  color: string;
}) {
  return (
    <div className="p-3 bg-zinc-800/40 rounded-lg border border-zinc-800/50">
      <div className="flex items-center gap-1.5">
        <Icon className={`w-3.5 h-3.5 ${color}`} />
        <span className="text-[10px] text-zinc-500 uppercase">{label}</span>
      </div>
      <p className={`text-lg font-bold mt-1 ${color}`}>{value}</p>
    </div>
  );
}

function StatusDot({ status }: { status: string }) {
  const colors: Record<string, string> = {
    queued: "bg-zinc-500",
    in_progress: "bg-blue-500",
    passed: "bg-green-500",
    failed: "bg-red-500",
    needs_revision: "bg-yellow-500",
    cancelled: "bg-zinc-600",
  };
  return (
    <div className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${colors[status] || "bg-zinc-600"}`} />
  );
}
