import { useState } from "react";
import type { PromptChainWithSteps } from "../../types/models";
import * as api from "../../tauri";
import { FocusTrap } from "../shared/FocusTrap";
import { useTranslation } from "react-i18next";

interface ChainFormDialogProps {
  chain: PromptChainWithSteps | null;
  onClose: () => void;
  onSaved: () => void;
}

export function ChainFormDialog({ chain, onClose, onSaved }: ChainFormDialogProps) {
  const { t } = useTranslation();
  const isEditing = chain !== null;
  const [name, setName] = useState(chain?.name ?? "");
  const [description, setDescription] = useState(chain?.description ?? "");
  const [category, setCategory] = useState(chain?.category ?? "general");

  const handleSubmit = async () => {
    if (isEditing) {
      await api.updatePromptChain(chain.id, name, description, category);
    } else {
      await api.createPromptChain(name, description, category);
    }
    onSaved();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" role="dialog" aria-modal="true" aria-labelledby="chain-form-title">
      <FocusTrap>
      <div className="bg-zinc-900 border border-zinc-700 rounded-xl w-[400px] p-5 shadow-2xl">
        <h3 id="chain-form-title" className="text-sm font-semibold text-zinc-200 mb-4">
          {isEditing ? t("prompts.chains.editChain") : t("prompts.chains.newChainTitle")}
        </h3>
        <div className="space-y-3">
          <input
            type="text"
            placeholder={t("prompts.chains.chainName")}
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:border-brand-500"
          />
          <textarea
            placeholder={t("prompts.chains.descriptionPlaceholder")}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={2}
            className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:border-brand-500 resize-none"
          />
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-300 focus:outline-none focus:border-brand-500"
          >
            <option value="general">{t("prompts.categories.general")}</option>
            <option value="coding">{t("prompts.categories.coding")}</option>
            <option value="review">{t("prompts.categories.review")}</option>
            <option value="testing">{t("prompts.categories.testing")}</option>
            <option value="analysis">{t("prompts.categories.analysis")}</option>
            <option value="content">{t("prompts.categories.content")}</option>
            <option value="devops">{t("prompts.categories.devops")}</option>
          </select>
        </div>
        <div className="flex justify-end gap-2 mt-4">
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-xs text-zinc-400 hover:text-zinc-200 transition-colors"
          >
            {t("prompts.chains.cancel")}
          </button>
          <button
            onClick={handleSubmit}
            disabled={!name.trim()}
            className="px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded disabled:opacity-50 transition-colors"
          >
            {isEditing ? t("prompts.chains.update") : t("prompts.chains.create")}
          </button>
        </div>
      </div>
      </FocusTrap>
    </div>
  );
}
