import { useState } from "react";
import { X } from "lucide-react";
import { useProjectStore } from "../../store/projectStore";
import { FocusTrap } from "../shared/FocusTrap";
import { useTranslation } from "react-i18next";

interface Props {
  onClose: () => void;
}

export function NewProjectDialog({ onClose }: Props) {
  const { createProject, selectProject } = useProjectStore();
  const { t } = useTranslation();
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [techStack, setTechStack] = useState("");
  const [projectType, setProjectType] = useState("software");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    const project = await createProject(
      name.trim(),
      description.trim(),
      techStack.trim(),
      projectType,
    );
    selectProject(project.id);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" role="dialog" aria-modal="true" aria-labelledby="new-project-title">
      <FocusTrap>
      <div className="bg-zinc-900 border border-zinc-700 rounded-xl shadow-2xl w-[480px] max-h-[90vh] overflow-hidden">
        <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-800">
          <h2 id="new-project-title" className="text-sm font-semibold text-zinc-200">{t("projects.newProjectDialog.title")}</h2>
          <button
            onClick={onClose}
            className="p-1 text-zinc-500 hover:text-zinc-300"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-xs font-medium text-zinc-400 mb-1.5">
              {t("projects.newProjectDialog.name")}
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t("projects.newProjectDialog.namePlaceholder")}
              autoFocus
              className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-200 placeholder-zinc-600 focus:outline-none focus:border-brand-500"
            />
          </div>

          <div>
            <label className="block text-xs font-medium text-zinc-400 mb-1.5">
              {t("projects.newProjectDialog.description")}
            </label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder={t("projects.newProjectDialog.descriptionPlaceholder")}
              rows={4}
              className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-200 placeholder-zinc-600 focus:outline-none focus:border-brand-500 resize-none"
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-zinc-400 mb-1.5">
                {t("projects.newProjectDialog.techStack")}
              </label>
              <input
                type="text"
                value={techStack}
                onChange={(e) => setTechStack(e.target.value)}
                placeholder={t("projects.newProjectDialog.techStackPlaceholder")}
                className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-200 placeholder-zinc-600 focus:outline-none focus:border-brand-500"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-zinc-400 mb-1.5">
                {t("projects.newProjectDialog.projectType")}
              </label>
              <select
                value={projectType}
                onChange={(e) => setProjectType(e.target.value)}
                className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-200 focus:outline-none focus:border-brand-500"
              >
                <option value="software">{t("projects.newProjectDialog.types.software")}</option>
                <option value="content">{t("projects.newProjectDialog.types.content")}</option>
                <option value="image">{t("projects.newProjectDialog.types.image")}</option>
                <option value="video">{t("projects.newProjectDialog.types.video")}</option>
                <option value="general">{t("projects.newProjectDialog.types.general")}</option>
              </select>
            </div>
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-xs text-zinc-400 hover:text-zinc-200 transition-colors"
            >
              {t("projects.newProjectDialog.cancel")}
            </button>
            <button
              type="submit"
              disabled={!name.trim()}
              className="px-4 py-2 bg-brand-600 hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed text-white text-xs rounded-md transition-colors"
            >
              {t("projects.newProjectDialog.create")}
            </button>
          </div>
        </form>
      </div>
      </FocusTrap>
    </div>
  );
}
