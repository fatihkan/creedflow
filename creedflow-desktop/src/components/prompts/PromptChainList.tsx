import { useEffect, useState } from "react";
import {
  Link2,
  Plus,
  Trash2,
  ChevronDown,
  ChevronRight,
  Pencil,
} from "lucide-react";
import type { PromptChainWithSteps, PromptChainStep } from "../../types/models";
import * as api from "../../tauri";
import { usePromptStore } from "../../store/promptStore";
import { ChainStepRow } from "./ChainStepRow";
import { ChainFormDialog } from "./ChainFormDialog";
import { useTranslation } from "react-i18next";
import { showErrorToast } from "../../hooks/useErrorToast";

export function PromptChainList() {
  const { t } = useTranslation();
  const [chains, setChains] = useState<PromptChainWithSteps[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [editingChain, setEditingChain] = useState<PromptChainWithSteps | null>(null);
  const [dragStepId, setDragStepId] = useState<string | null>(null);
  const prompts = usePromptStore((s) => s.prompts);
  const fetchPrompts = usePromptStore((s) => s.fetchPrompts);

  const fetchChains = async () => {
    setLoading(true);
    try {
      const data = await api.listPromptChains();
      setChains(data);
    } catch (e) {
      showErrorToast("Failed to fetch chains", e);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchChains();
    fetchPrompts();
  }, [fetchPrompts]);

  const handleDelete = async (id: string) => {
    await api.deletePromptChain(id);
    setChains((prev) => prev.filter((c) => c.id !== id));
  };

  const handleAddStep = async (chainId: string, promptId: string) => {
    const chain = chains.find((c) => c.id === chainId);
    const nextOrder = chain ? chain.steps.length + 1 : 1;
    await api.addChainStep(chainId, promptId, nextOrder);
    fetchChains();
  };

  const handleRemoveStep = async (stepId: string) => {
    await api.removeChainStep(stepId);
    fetchChains();
  };

  const handleDrop = async (_chainId: string, steps: PromptChainStep[], dropIdx: number) => {
    const dragStep = steps.find((s) => s.id === dragStepId);
    if (!dragStep || dragStep.id === steps[dropIdx]?.id) {
      setDragStepId(null);
      return;
    }
    const reordered = steps.filter((s) => s.id !== dragStep.id);
    reordered.splice(dropIdx, 0, dragStep);
    const updates: [string, number][] = reordered.map((s, i) => [s.id, i + 1]);
    await api.reorderChainSteps(updates);
    setDragStepId(null);
    fetchChains();
  };

  const handleTransitionNoteBlur = async (stepId: string, value: string) => {
    await api.updateChainStep(stepId, value || null);
  };

  const getPromptTitle = (promptId: string) => {
    return prompts.find((p) => p.id === promptId)?.title ?? "Unknown prompt";
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-32 text-zinc-500 text-sm">
        {t("prompts.chains.loading")}
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-4 space-y-3">
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs text-zinc-500">{t("prompts.chains.count", { count: chains.length })}</span>
        <button
          onClick={() => setShowCreate(true)}
          className="flex items-center gap-1.5 px-2.5 py-1 text-[11px] bg-brand-600/20 text-brand-400 hover:bg-brand-600/30 rounded transition-colors"
        >
          <Plus className="w-3 h-3" />
          {t("prompts.chains.newChain")}
        </button>
      </div>

      {chains.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-32 text-zinc-500">
          <Link2 className="w-8 h-8 mb-2 opacity-40" />
          <p className="text-sm">{t("prompts.chains.empty")}</p>
          <p className="text-xs mt-1 text-zinc-600">
            {t("prompts.chains.emptyDescription")}
          </p>
        </div>
      ) : (
        chains.map((chain) => {
          const isExpanded = expandedId === chain.id;
          return (
            <div
              key={chain.id}
              className="border border-zinc-800 rounded-lg bg-zinc-900/40 overflow-hidden"
            >
              <button
                onClick={() => setExpandedId(isExpanded ? null : chain.id)}
                className="w-full flex items-center gap-3 px-4 py-3 text-left hover:bg-zinc-800/30 transition-colors"
              >
                {isExpanded ? (
                  <ChevronDown className="w-3.5 h-3.5 text-zinc-500" />
                ) : (
                  <ChevronRight className="w-3.5 h-3.5 text-zinc-500" />
                )}
                <Link2 className="w-4 h-4 text-brand-400" />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-zinc-200 truncate">
                    {chain.name}
                  </p>
                  {chain.description && (
                    <p className="text-[11px] text-zinc-500 truncate mt-0.5">
                      {chain.description}
                    </p>
                  )}
                </div>
                <span className="text-[10px] text-zinc-500 bg-zinc-800 px-2 py-0.5 rounded-full">
                  {t("prompts.chains.steps", { count: chain.stepCount })}
                </span>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setEditingChain(chain);
                  }}
                  className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-zinc-200 transition-colors"
                  title={t("prompts.chains.editTitle")}
                  aria-label={`Edit ${chain.name}`}
                >
                  <Pencil className="w-3.5 h-3.5" />
                </button>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleDelete(chain.id);
                  }}
                  className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-red-400 transition-colors"
                  aria-label={`Delete ${chain.name}`}
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </button>

              {isExpanded && (
                <div className="border-t border-zinc-800 px-4 py-3 space-y-2">
                  {chain.steps.map((step, i) => (
                    <ChainStepRow
                      key={step.id}
                      step={step}
                      index={i}
                      promptTitle={getPromptTitle(step.promptId)}
                      onRemove={() => handleRemoveStep(step.id)}
                      onDragStart={() => setDragStepId(step.id)}
                      onDragOver={(e) => e.preventDefault()}
                      onDrop={() => handleDrop(chain.id, chain.steps, i)}
                      isDragging={dragStepId === step.id}
                      onTransitionNoteBlur={(val) =>
                        handleTransitionNoteBlur(step.id, val)
                      }
                    />
                  ))}

                  {/* Add step */}
                  <select
                    className="w-full text-xs bg-zinc-800 border border-zinc-700 rounded px-2 py-1.5 text-zinc-400 focus:outline-none focus:border-brand-500"
                    value=""
                    onChange={(e) => {
                      if (e.target.value) handleAddStep(chain.id, e.target.value);
                    }}
                  >
                    <option value="">{t("prompts.chains.addPrompt")}</option>
                    {prompts.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.title}
                      </option>
                    ))}
                  </select>
                </div>
              )}
            </div>
          );
        })
      )}

      {/* Create / Edit dialog */}
      {(showCreate || editingChain) && (
        <ChainFormDialog
          chain={editingChain}
          onClose={() => {
            setShowCreate(false);
            setEditingChain(null);
          }}
          onSaved={() => {
            fetchChains();
            setShowCreate(false);
            setEditingChain(null);
          }}
        />
      )}
    </div>
  );
}

