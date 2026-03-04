import { useState } from "react";
import { X } from "lucide-react";
import { usePromptStore } from "../../store/promptStore";
import { FocusTrap } from "../shared/FocusTrap";
import { useTranslation } from "react-i18next";

interface PromptEditDialogProps {
  onClose: () => void;
}

const CATEGORIES = [
  "coding",
  "review",
  "testing",
  "analysis",
  "content",
  "design",
  "devops",
  "general",
];

export function PromptEditDialog({ onClose }: PromptEditDialogProps) {
  const { t } = useTranslation();
  const createPrompt = usePromptStore((s) => s.createPrompt);
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [category, setCategory] = useState("general");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSave = async () => {
    if (!title.trim() || !content.trim()) {
      setError(t("prompts.editDialog.required"));
      return;
    }

    setSaving(true);
    setError(null);
    try {
      await createPrompt(title.trim(), content.trim(), category);
      onClose();
    } catch (e) {
      setError(String(e));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" role="dialog" aria-modal="true" aria-labelledby="prompt-edit-title">
      <FocusTrap>
      <div className="bg-zinc-900 border border-zinc-700 rounded-lg w-[520px] max-h-[80vh] flex flex-col shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
          <h3 id="prompt-edit-title" className="text-sm font-medium text-zinc-200">{t("prompts.editDialog.title")}</h3>
          <button
            onClick={onClose}
            className="p-1 text-zinc-500 hover:text-zinc-300 rounded"
            aria-label="Close dialog"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Form */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {/* Title */}
          <div>
            <label className="block text-xs font-medium text-zinc-400 mb-1">
              {t("prompts.editDialog.titleLabel")}
            </label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={t("prompts.editDialog.titlePlaceholder")}
              className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded text-zinc-200 placeholder-zinc-600 focus:outline-none focus:border-brand-500"
            />
          </div>

          {/* Category */}
          <div>
            <label className="block text-xs font-medium text-zinc-400 mb-1">
              {t("prompts.editDialog.category")}
            </label>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded text-zinc-200 focus:outline-none focus:border-brand-500"
            >
              {CATEGORIES.map((cat) => (
                <option key={cat} value={cat}>
                  {cat.charAt(0).toUpperCase() + cat.slice(1)}
                </option>
              ))}
            </select>
          </div>

          {/* Content */}
          <div>
            <label className="block text-xs font-medium text-zinc-400 mb-1">
              {t("prompts.editDialog.content")}
            </label>
            <textarea
              value={content}
              onChange={(e) => setContent(e.target.value)}
              placeholder={t("prompts.editDialog.contentPlaceholder")}
              rows={8}
              className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded text-zinc-200 placeholder-zinc-600 focus:outline-none focus:border-brand-500 resize-none font-mono"
            />
          </div>

          {error && (
            <p className="text-xs text-red-400" role="alert">{error}</p>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-2 px-4 py-3 border-t border-zinc-800">
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-xs text-zinc-400 hover:text-zinc-200 rounded transition-colors"
          >
            {t("prompts.editDialog.cancel")}
          </button>
          <button
            onClick={handleSave}
            disabled={saving || !title.trim() || !content.trim()}
            className="px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {saving ? t("prompts.editDialog.saving") : t("prompts.editDialog.create")}
          </button>
        </div>
      </div>
      </FocusTrap>
    </div>
  );
}
