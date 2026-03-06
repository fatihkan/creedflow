import { useCallback, useEffect, useMemo, useState } from "react";
import { Plus, Trash2, Terminal, FolderOpen, Code2, FileText } from "lucide-react";
import { useProjectStore } from "../../store/projectStore";
import { NewProjectDialog } from "./NewProjectDialog";
import { ProjectTemplateSelector } from "./ProjectTemplateSelector";
import { SearchBar } from "../shared/SearchBar";
import { FocusTrap } from "../shared/FocusTrap";
import { useTranslation } from "react-i18next";
import {
  openTerminal,
  openInFileManager,
  openInEditor,
  detectEditors,
  getPreferredEditor,
} from "../../tauri";
import type { DetectedEditor } from "../../types/models";
import { showErrorToast } from "../../hooks/useErrorToast";

export function ProjectList() {
  const { projects, fetchProjects, selectProject, selectedProjectId, deleteProject } =
    useProjectStore();
  const { t } = useTranslation();
  const [showNew, setShowNew] = useState(false);
  const [showTemplate, setShowTemplate] = useState(false);
  const [search, setSearch] = useState("");
  const [editors, setEditors] = useState<DetectedEditor[]>([]);
  const [preferredEditor, setPreferredEditor] = useState<string | null>(null);

  useEffect(() => {
    fetchProjects();
    detectEditors().then(setEditors).catch(() => {});
    getPreferredEditor().then(setPreferredEditor).catch(() => {});
  }, [fetchProjects]);

  const editorCommand = useMemo((): string | null => {
    if (preferredEditor) return preferredEditor;
    if (editors.length > 0) return editors[0].command;
    return null;
  }, [preferredEditor, editors]);

  const handleOpenTerminal = useCallback((e: React.MouseEvent, path: string) => {
    e.stopPropagation();
    openTerminal(path).catch((e) => showErrorToast("Failed to open terminal", e));
  }, []);

  const handleOpenFileManager = useCallback((e: React.MouseEvent, path: string) => {
    e.stopPropagation();
    openInFileManager(path).catch((e) => showErrorToast("Failed to open file manager", e));
  }, []);

  const handleOpenEditor = useCallback((e: React.MouseEvent, path: string) => {
    e.stopPropagation();
    if (editorCommand) {
      openInEditor(path, editorCommand).catch((e) => showErrorToast("Failed to open editor", e));
    }
  }, [editorCommand]);

  const filteredProjects = useMemo(() => {
    if (!search.trim()) return projects;
    const q = search.toLowerCase();
    return projects.filter((p) =>
      p.name.toLowerCase().includes(q) ||
      p.description.toLowerCase().includes(q) ||
      (p.techStack || "").toLowerCase().includes(q) ||
      p.status.toLowerCase().includes(q)
    );
  }, [projects, search]);

  return (
    <div className="flex-1 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <div>
          <h2 className="text-sm font-semibold text-zinc-200">{t("projects.title")}</h2>
          <p className="text-xs text-zinc-500 mt-0.5">
            {filteredProjects.length !== 1 ? t("projects.count_plural", { count: filteredProjects.length }) : t("projects.count", { count: filteredProjects.length })}
            {search && ` ${t("projects.matching", { search })}`}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <SearchBar
            value={search}
            onChange={setSearch}
            placeholder={t("projects.searchPlaceholder")}
          />
          <button
            onClick={() => setShowTemplate(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 text-xs rounded-md transition-colors"
            title={t("projects.newFromTemplate", "New from Template")}
          >
            <FileText className="w-3.5 h-3.5" />
          </button>
          <button
            onClick={() => setShowNew(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-brand-600 hover:bg-brand-700 text-white text-xs rounded-md transition-colors"
          >
            <Plus className="w-3.5 h-3.5" />
            {t("projects.newProject")}
          </button>
        </div>
      </div>

      {/* List */}
      <div className="flex-1 overflow-y-auto p-2">
        {filteredProjects.length === 0 ? (
          <div className="flex items-center justify-center h-full text-zinc-500 text-sm">
            {search ? t("projects.noMatch") : t("projects.empty")}
          </div>
        ) : (
          <div className="space-y-1">
            {filteredProjects.map((project) => (
              <button
                key={project.id}
                onClick={() => selectProject(project.id)}
                className={`w-full text-left px-3 py-3 rounded-lg transition-colors group ${
                  selectedProjectId === project.id
                    ? "bg-brand-600/10 border border-brand-600/30"
                    : "hover:bg-zinc-800/50 border border-transparent"
                }`}
              >
                <div className="flex items-center justify-between">
                  <div className="min-w-0 flex-1">
                    <h3 className="text-sm font-medium text-zinc-200 truncate">
                      {project.name}
                    </h3>
                    <p className="text-xs text-zinc-500 truncate mt-0.5">
                      {project.description}
                    </p>
                  </div>
                  <div className="flex items-center gap-1 ml-2">
                    <span
                      className={`text-[10px] px-1.5 py-0.5 rounded ${
                        project.status === "completed"
                          ? "bg-green-900/50 text-green-400"
                          : project.status === "failed"
                            ? "bg-red-900/50 text-red-400"
                            : "bg-zinc-800 text-zinc-400"
                      }`}
                    >
                      {project.status}
                    </span>
                    {/* Action buttons — visible on hover */}
                    {project.directoryPath && (
                      <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button
                          onClick={(e) => handleOpenTerminal(e, project.directoryPath)}
                          className="p-1 text-zinc-600 hover:text-zinc-200"
                          title="Open in Terminal"
                          aria-label={`Open ${project.name} in terminal`}
                        >
                          <Terminal className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={(e) => handleOpenFileManager(e, project.directoryPath)}
                          className="p-1 text-zinc-600 hover:text-zinc-200"
                          title="Open in File Manager"
                          aria-label={`Open ${project.name} in file manager`}
                        >
                          <FolderOpen className="w-3.5 h-3.5" />
                        </button>
                        {editorCommand && (
                          <button
                            onClick={(e) => handleOpenEditor(e, project.directoryPath)}
                            className="p-1 text-zinc-600 hover:text-zinc-200"
                            title={`Open in ${editors.find((e) => e.command === editorCommand)?.name ?? "Editor"}`}
                          >
                            <Code2 className="w-3.5 h-3.5" />
                          </button>
                        )}
                      </div>
                    )}
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        deleteProject(project.id);
                      }}
                      className="p-1 text-zinc-600 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
                      aria-label={`Delete ${project.name}`}
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
                {project.techStack && (
                  <p className="text-[10px] text-zinc-600 mt-1">
                    {project.techStack}
                  </p>
                )}
              </button>
            ))}
          </div>
        )}
      </div>

      {showNew && <NewProjectDialog onClose={() => setShowNew(false)} />}
      {showTemplate && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" role="dialog" aria-modal="true" aria-label="Project template selector">
          <FocusTrap>
          <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4 w-[520px] max-h-[600px] overflow-y-auto">
            <ProjectTemplateSelector
              onCreated={(id) => {
                setShowTemplate(false);
                selectProject(id);
                fetchProjects();
              }}
              onCancel={() => setShowTemplate(false)}
            />
          </div>
          </FocusTrap>
        </div>
      )}
    </div>
  );
}
