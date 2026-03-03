import { useEffect, useState } from "react";
import { Plus, Trash2, Terminal, FolderOpen, Code2 } from "lucide-react";
import { useProjectStore } from "../../store/projectStore";
import { NewProjectDialog } from "./NewProjectDialog";
import { SearchBar } from "../shared/SearchBar";
import {
  openTerminal,
  openInFileManager,
  openInEditor,
  detectEditors,
  getPreferredEditor,
} from "../../tauri";
import type { DetectedEditor } from "../../types/models";

export function ProjectList() {
  const { projects, fetchProjects, selectProject, selectedProjectId, deleteProject } =
    useProjectStore();
  const [showNew, setShowNew] = useState(false);
  const [search, setSearch] = useState("");
  const [editors, setEditors] = useState<DetectedEditor[]>([]);
  const [preferredEditor, setPreferredEditor] = useState<string | null>(null);

  useEffect(() => {
    fetchProjects();
    detectEditors().then(setEditors).catch(() => {});
    getPreferredEditor().then(setPreferredEditor).catch(() => {});
  }, [fetchProjects]);

  const getEditorCommand = (): string | null => {
    if (preferredEditor) return preferredEditor;
    if (editors.length > 0) return editors[0].command;
    return null;
  };

  const handleOpenTerminal = (e: React.MouseEvent, path: string) => {
    e.stopPropagation();
    openTerminal(path).catch((err) => console.error("Failed to open terminal:", err));
  };

  const handleOpenFileManager = (e: React.MouseEvent, path: string) => {
    e.stopPropagation();
    openInFileManager(path).catch((err) => console.error("Failed to open file manager:", err));
  };

  const handleOpenEditor = (e: React.MouseEvent, path: string) => {
    e.stopPropagation();
    const cmd = getEditorCommand();
    if (cmd) {
      openInEditor(path, cmd).catch((err) => console.error("Failed to open editor:", err));
    }
  };

  const filteredProjects = search.trim()
    ? projects.filter((p) => {
        const q = search.toLowerCase();
        return (
          p.name.toLowerCase().includes(q) ||
          p.description.toLowerCase().includes(q) ||
          (p.techStack || "").toLowerCase().includes(q) ||
          p.status.toLowerCase().includes(q)
        );
      })
    : projects;

  return (
    <div className="flex-1 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <div>
          <h2 className="text-sm font-semibold text-zinc-200">Projects</h2>
          <p className="text-xs text-zinc-500 mt-0.5">
            {filteredProjects.length} project{filteredProjects.length !== 1 ? "s" : ""}
            {search && ` matching "${search}"`}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <SearchBar
            value={search}
            onChange={setSearch}
            placeholder="Search projects..."
          />
          <button
            onClick={() => setShowNew(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-brand-600 hover:bg-brand-700 text-white text-xs rounded-md transition-colors"
          >
            <Plus className="w-3.5 h-3.5" />
            New Project
          </button>
        </div>
      </div>

      {/* List */}
      <div className="flex-1 overflow-y-auto p-2">
        {filteredProjects.length === 0 ? (
          <div className="flex items-center justify-center h-full text-zinc-500 text-sm">
            {search ? "No projects match your search" : "No projects yet. Create one to get started."}
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
                        >
                          <Terminal className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={(e) => handleOpenFileManager(e, project.directoryPath)}
                          className="p-1 text-zinc-600 hover:text-zinc-200"
                          title="Open in File Manager"
                        >
                          <FolderOpen className="w-3.5 h-3.5" />
                        </button>
                        {getEditorCommand() && (
                          <button
                            onClick={(e) => handleOpenEditor(e, project.directoryPath)}
                            className="p-1 text-zinc-600 hover:text-zinc-200"
                            title={`Open in ${editors.find((e) => e.command === getEditorCommand())?.name ?? "Editor"}`}
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
    </div>
  );
}
