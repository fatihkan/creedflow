import { useEffect, useState } from "react";
import {
  Link2,
  Plus,
  Trash2,
  ChevronDown,
  ChevronRight,
  GripVertical,
} from "lucide-react";
import type { PromptChainWithSteps } from "../../types/models";
import * as api from "../../tauri";
import { usePromptStore } from "../../store/promptStore";

export function PromptChainList() {
  const [chains, setChains] = useState<PromptChainWithSteps[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const prompts = usePromptStore((s) => s.prompts);
  const fetchPrompts = usePromptStore((s) => s.fetchPrompts);

  const fetchChains = async () => {
    setLoading(true);
    try {
      const data = await api.listPromptChains();
      setChains(data);
    } catch (e) {
      console.error("Failed to fetch chains:", e);
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

  const getPromptTitle = (promptId: string) => {
    return prompts.find((p) => p.id === promptId)?.title ?? "Unknown prompt";
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-32 text-zinc-500 text-sm">
        Loading chains...
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-4 space-y-3">
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs text-zinc-500">{chains.length} chains</span>
        <button
          onClick={() => setShowCreate(true)}
          className="flex items-center gap-1.5 px-2.5 py-1 text-[11px] bg-brand-600/20 text-brand-400 hover:bg-brand-600/30 rounded transition-colors"
        >
          <Plus className="w-3 h-3" />
          New Chain
        </button>
      </div>

      {chains.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-32 text-zinc-500">
          <Link2 className="w-8 h-8 mb-2 opacity-40" />
          <p className="text-sm">No prompt chains yet</p>
          <p className="text-xs mt-1 text-zinc-600">
            Chain prompts together for multi-step workflows
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
                  {chain.stepCount} steps
                </span>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleDelete(chain.id);
                  }}
                  className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-red-400 transition-colors"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </button>

              {isExpanded && (
                <div className="border-t border-zinc-800 px-4 py-3 space-y-2">
                  {chain.steps.map((step, i) => (
                    <div
                      key={step.id}
                      className="flex items-center gap-2 px-3 py-2 bg-zinc-800/40 rounded-md"
                    >
                      <GripVertical className="w-3 h-3 text-zinc-600" />
                      <span className="text-[10px] text-zinc-500 w-5">
                        {i + 1}.
                      </span>
                      <span className="text-xs text-zinc-300 flex-1 truncate">
                        {getPromptTitle(step.promptId)}
                      </span>
                      {step.transitionNote && (
                        <span className="text-[10px] text-zinc-500 truncate max-w-[120px]">
                          {step.transitionNote}
                        </span>
                      )}
                      <button
                        onClick={() => handleRemoveStep(step.id)}
                        className="p-0.5 rounded hover:bg-zinc-700 text-zinc-500 hover:text-red-400 transition-colors"
                      >
                        <Trash2 className="w-3 h-3" />
                      </button>
                    </div>
                  ))}

                  {/* Add step */}
                  <select
                    className="w-full text-xs bg-zinc-800 border border-zinc-700 rounded px-2 py-1.5 text-zinc-400 focus:outline-none focus:border-brand-500"
                    value=""
                    onChange={(e) => {
                      if (e.target.value) handleAddStep(chain.id, e.target.value);
                    }}
                  >
                    <option value="">+ Add prompt to chain...</option>
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

      {/* Create dialog */}
      {showCreate && (
        <CreateChainDialog
          onClose={() => setShowCreate(false)}
          onCreate={async (name, description, category) => {
            await api.createPromptChain(name, description, category);
            fetchChains();
            setShowCreate(false);
          }}
        />
      )}
    </div>
  );
}

function CreateChainDialog({
  onClose,
  onCreate,
}: {
  onClose: () => void;
  onCreate: (name: string, description: string, category: string) => Promise<void>;
}) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState("general");

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
      <div className="bg-zinc-900 border border-zinc-700 rounded-xl w-[400px] p-5 shadow-2xl">
        <h3 className="text-sm font-semibold text-zinc-200 mb-4">
          New Prompt Chain
        </h3>
        <div className="space-y-3">
          <input
            type="text"
            placeholder="Chain name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:border-brand-500"
          />
          <textarea
            placeholder="Description (optional)"
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
            <option value="general">General</option>
            <option value="coding">Coding</option>
            <option value="review">Review</option>
            <option value="testing">Testing</option>
            <option value="analysis">Analysis</option>
            <option value="content">Content</option>
            <option value="devops">DevOps</option>
          </select>
        </div>
        <div className="flex justify-end gap-2 mt-4">
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-xs text-zinc-400 hover:text-zinc-200 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={() => onCreate(name, description, category)}
            disabled={!name.trim()}
            className="px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded disabled:opacity-50 transition-colors"
          >
            Create
          </button>
        </div>
      </div>
    </div>
  );
}
