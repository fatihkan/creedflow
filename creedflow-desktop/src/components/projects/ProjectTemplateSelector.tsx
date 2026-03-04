import { useEffect, useState } from "react";
import { ArrowLeft, Loader2 } from "lucide-react";
import * as api from "../../tauri";
import type { ProjectTemplate } from "../../types/models";
import { useTranslation } from "react-i18next";

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

export function ProjectTemplateSelector({ onCreated, onCancel }: ProjectTemplateSelectorProps) {
  const { t } = useTranslation();
  const [templates, setTemplates] = useState<ProjectTemplate[]>([]);
  const [selected, setSelected] = useState<ProjectTemplate | null>(null);
  const [name, setName] = useState("");
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.listProjectTemplates().then(setTemplates).catch(console.error);
  }, []);

  const handleCreate = async () => {
    if (!selected || !name.trim()) return;
    setCreating(true);
    setError(null);
    try {
      const project = await api.createProjectFromTemplate(selected.id, name.trim());
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
      <div className="space-y-4">
        <button
          onClick={() => setSelected(null)}
          className="flex items-center gap-1 text-xs text-zinc-400 hover:text-zinc-200"
        >
          <ArrowLeft className="w-3 h-3" />
          {t("templates.backToTemplates")}
        </button>

        <div className="flex items-center gap-3">
          <span className="text-2xl">{templateIcons[selected.icon] || "\ud83d\udce6"}</span>
          <div>
            <h3 className="text-sm font-semibold text-zinc-200">{selected.name}</h3>
            <p className="text-xs text-zinc-400">{selected.description}</p>
          </div>
        </div>

        <input
          type="text"
          placeholder={t("templates.projectName")}
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-brand-500"
          autoFocus
        />

        <p className="text-xs text-zinc-500">
          {t("templates.createInfo", { features: selected.features.length, tasks: totalTasks })}
          {" "}{t("templates.tech")} <span className="font-mono text-zinc-400">{selected.techStack}</span>
        </p>

        {error && (
          <p className="text-xs text-red-400 bg-red-500/10 px-3 py-2 rounded">{error}</p>
        )}

        <div className="flex justify-end gap-2">
          <button
            onClick={onCancel}
            className="px-3 py-1.5 text-xs text-zinc-400 hover:text-zinc-200"
          >
            {t("templates.cancel")}
          </button>
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
            onClick={() => { setSelected(tmpl); setName(""); }}
            className="p-3 text-left bg-zinc-800/40 rounded-lg border border-zinc-800/50 hover:border-zinc-700 transition-colors"
          >
            <div className="flex items-center justify-between mb-1">
              <span className="text-lg">{templateIcons[tmpl.icon] || "\ud83d\udce6"}</span>
              <span className="text-[10px] text-zinc-600 capitalize">{tmpl.projectType}</span>
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
