import { useEffect, useState } from "react";
import { Plus, Trash2, Pencil, ToggleLeft, ToggleRight } from "lucide-react";
import type { AgentPersona, AgentType } from "../../types/models";
import { usePersonaStore } from "../../store/personaStore";
import { useErrorToast } from "../../hooks/useErrorToast";
import { useTranslation } from "react-i18next";

const AGENT_TYPES: AgentType[] = [
  "analyzer",
  "coder",
  "reviewer",
  "tester",
  "devops",
  "monitor",
  "contentWriter",
  "designer",
  "imageGenerator",
  "videoEditor",
  "publisher",
  "planner",
];

export function PersonasSettings() {
  const { t } = useTranslation();
  const { personas, fetchPersonas, createPersona, updatePersona, deletePersona } =
    usePersonaStore();
  const withError = useErrorToast();
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<AgentPersona | null>(null);

  useEffect(() => {
    fetchPersonas();
  }, [fetchPersonas]);

  const handleToggle = async (persona: AgentPersona) => {
    await withError(() =>
      updatePersona(
        persona.id,
        persona.name,
        persona.description,
        persona.systemPrompt,
        persona.agentTypes,
        persona.tags,
        !persona.isEnabled,
      ),
    );
  };

  const handleDelete = async (id: string) => {
    await withError(() => deletePersona(id));
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-zinc-200">
            {t("personas.title", "Personas")}
          </h3>
          <p className="text-xs text-zinc-500 mt-0.5">
            {t(
              "personas.description",
              "Manage skill personas that shape how agents approach tasks.",
            )}
          </p>
        </div>
        <button
          onClick={() => {
            setEditing(null);
            setShowForm(true);
          }}
          className="flex items-center gap-1 px-2.5 py-1.5 text-xs rounded-md bg-brand-600 hover:bg-brand-500 text-white transition-colors"
        >
          <Plus className="w-3.5 h-3.5" />
          {t("personas.add", "Add")}
        </button>
      </div>

      {personas.length === 0 ? (
        <p className="text-xs text-zinc-500 text-center py-6">
          {t("personas.empty", "No personas yet.")}
        </p>
      ) : (
        <div className="space-y-2">
          {personas.map((persona) => (
            <div
              key={persona.id}
              className="flex items-start gap-3 p-3 rounded-lg bg-zinc-800/50 border border-zinc-700/50"
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-zinc-200 truncate">
                    {persona.name}
                  </span>
                  {persona.isBuiltIn && (
                    <span className="px-1.5 py-0.5 text-[10px] font-medium rounded bg-blue-500/15 text-blue-400">
                      {t("personas.builtIn", "Built-in")}
                    </span>
                  )}
                </div>
                {persona.description && (
                  <p className="text-xs text-zinc-500 mt-0.5 truncate">
                    {persona.description}
                  </p>
                )}
                {persona.agentTypes.length > 0 && (
                  <div className="flex flex-wrap gap-1 mt-1.5">
                    {persona.agentTypes.map((type) => (
                      <span
                        key={type}
                        className="px-1.5 py-0.5 text-[10px] rounded bg-purple-500/15 text-purple-400"
                      >
                        {type}
                      </span>
                    ))}
                  </div>
                )}
              </div>
              <div className="flex items-center gap-2 shrink-0">
                <button
                  onClick={() => handleToggle(persona)}
                  className="text-zinc-400 hover:text-zinc-200"
                  title={persona.isEnabled ? "Disable" : "Enable"}
                >
                  {persona.isEnabled ? (
                    <ToggleRight className="w-5 h-5 text-green-400" />
                  ) : (
                    <ToggleLeft className="w-5 h-5" />
                  )}
                </button>
                <button
                  onClick={() => {
                    setEditing(persona);
                    setShowForm(true);
                  }}
                  className="text-zinc-400 hover:text-zinc-200"
                >
                  <Pencil className="w-3.5 h-3.5" />
                </button>
                {!persona.isBuiltIn && (
                  <button
                    onClick={() => handleDelete(persona.id)}
                    className="text-zinc-400 hover:text-red-400"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {showForm && (
        <PersonaFormModal
          persona={editing}
          onClose={() => setShowForm(false)}
          onSave={async (data) => {
            const result = await withError(async () => {
              if (editing) {
                await updatePersona(
                  editing.id,
                  data.name,
                  data.description,
                  data.systemPrompt,
                  data.agentTypes,
                  data.tags,
                  editing.isEnabled,
                );
              } else {
                await createPersona(
                  data.name,
                  data.description,
                  data.systemPrompt,
                  data.agentTypes,
                  data.tags,
                );
              }
              return true;
            });
            if (result) setShowForm(false);
          }}
        />
      )}
    </div>
  );
}

// ─── Form Modal ─────────────────────────────────────────────────────────────

interface PersonaFormData {
  name: string;
  description: string;
  systemPrompt: string;
  agentTypes: string[];
  tags: string[];
}

function PersonaFormModal({
  persona,
  onClose,
  onSave,
}: {
  persona: AgentPersona | null;
  onClose: () => void;
  onSave: (data: PersonaFormData) => Promise<void>;
}) {
  const { t } = useTranslation();
  const [name, setName] = useState(persona?.name ?? "");
  const [description, setDescription] = useState(persona?.description ?? "");
  const [systemPrompt, setSystemPrompt] = useState(persona?.systemPrompt ?? "");
  const [agentTypes, setAgentTypes] = useState<string[]>(persona?.agentTypes ?? []);
  const [tagsText, setTagsText] = useState(persona?.tags.join(", ") ?? "");
  const [saving, setSaving] = useState(false);

  const toggleType = (type: string) => {
    setAgentTypes((prev) =>
      prev.includes(type) ? prev.filter((t) => t !== type) : [...prev, type],
    );
  };

  const handleSubmit = async () => {
    setSaving(true);
    const tags = tagsText
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean);
    await onSave({ name, description, systemPrompt, agentTypes, tags });
    setSaving(false);
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-zinc-900 border border-zinc-700 rounded-xl w-[480px] max-h-[80vh] overflow-y-auto p-5 space-y-4">
        <h3 className="text-sm font-semibold text-zinc-200">
          {persona
            ? t("personas.edit", "Edit Persona")
            : t("personas.add", "Add Persona")}
        </h3>

        <div className="space-y-3">
          <div>
            <label className="text-xs text-zinc-400 mb-1 block">
              {t("personas.name", "Name")}
            </label>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              disabled={persona?.isBuiltIn}
              className="w-full px-3 py-1.5 text-sm rounded-md bg-zinc-800 border border-zinc-700 text-zinc-200 focus:outline-none focus:border-brand-500 disabled:opacity-50"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400 mb-1 block">
              {t("personas.description", "Description")}
            </label>
            <input
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="w-full px-3 py-1.5 text-sm rounded-md bg-zinc-800 border border-zinc-700 text-zinc-200 focus:outline-none focus:border-brand-500"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400 mb-1 block">
              {t("personas.systemPrompt", "System Prompt")}
            </label>
            <textarea
              value={systemPrompt}
              onChange={(e) => setSystemPrompt(e.target.value)}
              rows={5}
              className="w-full px-3 py-1.5 text-sm rounded-md bg-zinc-800 border border-zinc-700 text-zinc-200 font-mono text-xs focus:outline-none focus:border-brand-500 resize-y"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400 mb-1 block">
              {t("personas.agentTypes", "Agent Types")}
            </label>
            <div className="flex flex-wrap gap-1.5">
              {AGENT_TYPES.map((type) => (
                <button
                  key={type}
                  onClick={() => toggleType(type)}
                  className={`px-2 py-1 text-[11px] rounded-md border transition-colors ${
                    agentTypes.includes(type)
                      ? "bg-purple-500/20 border-purple-500/50 text-purple-300"
                      : "bg-zinc-800 border-zinc-700 text-zinc-500 hover:text-zinc-300"
                  }`}
                >
                  {type}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="text-xs text-zinc-400 mb-1 block">
              {t("personas.tags", "Tags")}
            </label>
            <input
              value={tagsText}
              onChange={(e) => setTagsText(e.target.value)}
              placeholder="architecture, design, security..."
              className="w-full px-3 py-1.5 text-sm rounded-md bg-zinc-800 border border-zinc-700 text-zinc-200 focus:outline-none focus:border-brand-500"
            />
            <p className="text-[10px] text-zinc-600 mt-1">Comma-separated</p>
          </div>
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-xs rounded-md text-zinc-400 hover:text-zinc-200 transition-colors"
          >
            {t("common.cancel", "Cancel")}
          </button>
          <button
            onClick={handleSubmit}
            disabled={!name || !systemPrompt || saving}
            className="px-3 py-1.5 text-xs rounded-md bg-brand-600 hover:bg-brand-500 text-white disabled:opacity-50 transition-colors"
          >
            {saving ? "..." : persona ? t("common.save", "Save") : t("personas.add", "Add")}
          </button>
        </div>
      </div>
    </div>
  );
}
