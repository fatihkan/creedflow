import { useEffect, useState } from "react";
import { ArrowLeft, Loader2 } from "lucide-react";
import * as api from "../../tauri";
import type { ProjectTemplate } from "../../types/models";
import { useTranslation } from "react-i18next";
import { showErrorToast } from "../../hooks/useErrorToast";

interface ProjectTemplateSelectorProps {
  onCreated: (projectId: string) => void;
  onCancel: () => void;
}

const templateIcons: Record<string, string> = {
  globe: "\ud83c\udf10",
  smartphone: "\ud83d\udcf1",
  server: "\ud83d\udda5\ufe0f",
  "file-text": "\ud83d\udcc4",
  newspaper: "\ud83d\udcf0",
  terminal: "\ud83d\udcbb",
};

// Project type labels are resolved via t() at render time.

export function ProjectTemplateSelector({ onCreated, onCancel }: ProjectTemplateSelectorProps) {
  const { t } = useTranslation();
  const [templates, setTemplates] = useState<ProjectTemplate[]>([]);
  const [selected, setSelected] = useState<ProjectTemplate | null>(null);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [techStack, setTechStack] = useState("");
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.listProjectTemplates().then(setTemplates).catch((e) => showErrorToast("Failed to load project templates", e));
  }, []);

  const handleSelect = (tmpl: ProjectTemplate) => {
    setSelected(tmpl);
    setName("");
    setDescription(tmpl.description);
    setTechStack(tmpl.techStack);
    setError(null);
  };

  const handleCreate = async () => {
    if (!selected || !name.trim()) return;
    setCreating(true);
    setError(null);
    try {
      const project = await api.createProjectFromTemplate(
        selected.id,
        name.trim(),
        description.trim() || undefined,
        techStack.trim() || undefined,
      );
      onCreated(project.id);
    } catch (e) {
      setError(String(e));
    } finally {
      setCreating(false);
    }
  };

  if (selected) {
    const totalTasks = selected.features.reduce((sum, f) => sum + f.tasks.length, 0);
    return (
      <div className="flex flex-col min-h-[420px]">
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <button
            onClick={() => setSelected(null)}
            className="flex items-center gap-1 text-xs text-zinc-400 hover:text-zinc-200"
          >
            <ArrowLeft className="w-3 h-3" />
            {t("templates.backToTemplates")}
          </button>
          <div className="flex items-center gap-2">
            <span className={`text-[10px] px-2 py-0.5 rounded-full font-medium ${
              selected.projectType === "software"
                ? "bg-blue-500/15 text-blue-400"
                : selected.projectType === "content"
                  ? "bg-purple-500/15 text-purple-400"
                  : "bg-zinc-700 text-zinc-400"
            }`}>
              {t(`templates.types.${selected.projectType}`, selected.projectType)}
            </span>
            <button onClick={onCancel} className="text-xs text-zinc-500 hover:text-zinc-300">
              {t("templates.cancel")}
            </button>
          </div>
        </div>

        {/* Template info */}
        <div className="flex items-center gap-3 mb-3">
          <span className="text-2xl">{templateIcons[selected.icon] || "\ud83d\udce6"}</span>
          <div className="flex-1 min-w-0">
            <h3 className="text-sm font-semibold text-zinc-200">{selected.name}</h3>
          </div>
        </div>

        {/* Name input */}
        <div className="mb-3">
          <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider mb-1 block">
            {t("templates.projectName")}
          </label>
          <input
            type="text"
            placeholder={t("templates.projectName")}
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-brand-500"
            autoFocus
          />
        </div>

        {/* Description / Prompt */}
        <div className="mb-3">
          <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider mb-1 block">
            {t("templates.description", "Description")}
          </label>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={3}
            className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-brand-500 resize-none"
            placeholder={t("templates.descriptionPlaceholder", "Describe your project...")}
          />
        </div>

        {/* Tech Stack */}
        <div className="mb-3">
          <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider mb-1 block">
            {t("templates.techStack", "Tech Stack")}
          </label>
          <input
            type="text"
            value={techStack}
            onChange={(e) => setTechStack(e.target.value)}
            className="w-full px-3 py-1.5 text-xs bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-brand-500 font-mono"
          />
        </div>

        {/* Features & tasks preview */}
        <div className="flex-1 overflow-y-auto mb-3">
          <p className="text-[10px] font-semibold text-zinc-500 uppercase tracking-wider mb-2">
            {t("templates.createInfo", { features: selected.features.length, tasks: totalTasks })}
          </p>
          <div className="space-y-2">
            {selected.features.map((feature, i) => (
              <div key={i} className="p-2.5 bg-zinc-800/40 rounded-md border border-zinc-800/60">
                <div className="flex items-center justify-between mb-1">
                  <span className="text-xs font-medium text-zinc-300">{feature.name}</span>
                  <span className="text-[10px] text-zinc-600">{feature.tasks.length} {feature.tasks.length === 1 ? t("templates.task") : t("templates.tasks")}</span>
                </div>
                <p className="text-[10px] text-zinc-500 mb-1.5">{feature.description}</p>
                <div className="flex flex-wrap gap-1">
                  {feature.tasks.map((task, j) => (
                    <span key={j} className="text-[10px] text-zinc-500 bg-zinc-800 px-1.5 py-0.5 rounded">
                      {task.title}
                    </span>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>

        {error && (
          <p className="text-xs text-red-400 bg-red-500/10 px-3 py-2 rounded mb-3">{error}</p>
        )}

        {/* Actions */}
        <div className="flex justify-end pt-3 border-t border-zinc-800">
          <button
            onClick={handleCreate}
            disabled={!name.trim() || creating}
            className="px-3 py-1.5 text-xs bg-brand-600 text-white rounded-md hover:bg-brand-500 disabled:opacity-50 flex items-center gap-1.5"
          >
            {creating && <Loader2 className="w-3 h-3 animate-spin" />}
            {t("templates.createProject")}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold text-zinc-200">{t("templates.title")}</h3>
        <button onClick={onCancel} className="text-xs text-zinc-500 hover:text-zinc-300">
          {t("templates.cancel")}
        </button>
      </div>
      <div className="grid grid-cols-2 gap-2">
        {templates.map((tmpl) => (
          <button
            key={tmpl.id}
            onClick={() => handleSelect(tmpl)}
            className="p-3 text-left bg-zinc-800/40 rounded-lg border border-zinc-800/50 hover:border-zinc-700 transition-colors"
          >
            <div className="flex items-center justify-between mb-1">
              <span className="text-lg">{templateIcons[tmpl.icon] || "\ud83d\udce6"}</span>
              <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-medium ${
                tmpl.projectType === "software"
                  ? "bg-blue-500/10 text-blue-400"
                  : tmpl.projectType === "content"
                    ? "bg-purple-500/10 text-purple-400"
                    : "bg-zinc-800 text-zinc-500"
              }`}>
                {t(`templates.types.${tmpl.projectType}`, tmpl.projectType)}
              </span>
            </div>
            <p className="text-xs font-semibold text-zinc-200">{tmpl.name}</p>
            <p className="text-[10px] text-zinc-500 mt-0.5 line-clamp-2">{tmpl.description}</p>
            <p className="text-[10px] text-zinc-600 font-mono mt-1">{tmpl.techStack}</p>
          </button>
        ))}
      </div>
    </div>
  );
}
