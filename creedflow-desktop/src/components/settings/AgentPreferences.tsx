import { useEffect, useState } from "react";
import { useSettingsStore } from "../../store/settingsStore";
import * as api from "../../tauri";
import type { AgentBackendOverrides, AgentType } from "../../types/models";

interface AgentBackendInfo {
  agentType: string;
  defaultPreference: string;
  allowedBackends: string[];
}

const BACKEND_LABELS: Record<string, string> = {
  claude: "Claude",
  codex: "Codex",
  gemini: "Gemini",
  ollama: "Ollama",
  lmStudio: "LM Studio",
  llamaCpp: "llama.cpp",
  mlx: "MLX",
};

const AGENT_OVERRIDE_KEYS: AgentType[] = [
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

export function AgentPreferences() {
  const { settings, updateSettings } = useSettingsStore();
  const [agentInfo, setAgentInfo] = useState<AgentBackendInfo[]>([]);

  useEffect(() => {
    api.getAgentBackendInfo().then(setAgentInfo).catch(console.error);
  }, []);

  if (!settings || agentInfo.length === 0) return null;

  const overrides = settings.agentBackendOverrides ?? ({} as AgentBackendOverrides);

  const handleChange = (agentType: AgentType, value: string) => {
    const newOverrides: AgentBackendOverrides = {
      ...({
        analyzer: null,
        coder: null,
        reviewer: null,
        tester: null,
        devops: null,
        monitor: null,
        contentWriter: null,
        designer: null,
        imageGenerator: null,
        videoEditor: null,
        publisher: null,
        planner: null,
      } satisfies AgentBackendOverrides),
      ...overrides,
      [agentType]: value === "default" ? null : value,
    };
    updateSettings({
      ...settings,
      agentBackendOverrides: newOverrides,
    });
  };

  return (
    <section>
      <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
        Agent Backend Preferences
      </h3>
      <p className="text-xs text-zinc-500 mb-3">
        Override the default backend for each agent. &quot;Default&quot; uses the
        built-in preference.
      </p>
      <div className="space-y-1">
        {agentInfo.map((info) => {
          const agentType = info.agentType as AgentType;
          const currentOverride =
            (overrides as unknown as Record<string, string | null>)[agentType] ?? null;

          return (
            <div
              key={agentType}
              className="flex items-center justify-between py-2 px-3 rounded-md bg-zinc-800/30"
            >
              <div>
                <span className="text-xs text-zinc-200 font-medium">
                  {AGENT_OVERRIDE_KEYS.includes(agentType)
                    ? agentType.charAt(0).toUpperCase() +
                      agentType.slice(1).replace(/([A-Z])/g, " $1")
                    : agentType}
                </span>
                <span className="text-[10px] text-zinc-500 ml-2">
                  ({info.defaultPreference})
                </span>
              </div>
              <select
                value={currentOverride ?? "default"}
                onChange={(e) => handleChange(agentType, e.target.value)}
                className="bg-zinc-800 border border-zinc-700 rounded px-2 py-1 text-xs text-zinc-300"
              >
                <option value="default">Default</option>
                {info.allowedBackends.map((b) => (
                  <option key={b} value={b}>
                    {BACKEND_LABELS[b] || b}
                  </option>
                ))}
              </select>
            </div>
          );
        })}
      </div>
    </section>
  );
}
