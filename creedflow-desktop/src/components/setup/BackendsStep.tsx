import { useEffect, useState } from "react";
import * as api from "../../tauri";
import type { AppSettings } from "../../types/models";
import { useTranslation } from "react-i18next";
import { showErrorToast } from "../../hooks/useErrorToast";

interface BackendsStepProps {
  settings: AppSettings;
  onUpdate: (s: AppSettings) => Promise<void>;
}

export function BackendsStep({ settings, onUpdate }: BackendsStepProps) {
  const { t } = useTranslation();
  const [availability, setAvailability] = useState<Record<string, boolean>>({});
  const [synced, setSynced] = useState(false);

  const backends = [
    { key: "claudeEnabled" as const, cli: "claude", label: "Claude", cloud: true },
    { key: "codexEnabled" as const, cli: "codex", label: "Codex", cloud: true },
    { key: "geminiEnabled" as const, cli: "gemini", label: "Gemini", cloud: true },
    { key: "opencodeEnabled" as const, cli: "opencode", label: "OpenCode", cloud: true },
    { key: "ollamaEnabled" as const, cli: "ollama", label: "Ollama", cloud: false },
    { key: "lmStudioEnabled" as const, cli: "lmStudio", label: "LM Studio", cloud: false },
    { key: "llamaCppEnabled" as const, cli: "llamaCpp", label: "llama.cpp", cloud: false },
    { key: "mlxEnabled" as const, cli: "mlx", label: "MLX", cloud: false },
  ];

  useEffect(() => {
    api.listBackends().then((infos) => {
      const avail: Record<string, boolean> = {};
      for (const info of infos) {
        avail[info.backendType] = info.isAvailable;
      }
      setAvailability(avail);
    }).catch((e) => showErrorToast("Failed to list backends", e));
  }, []);

  // Auto-sync enabled state based on availability (once)
  useEffect(() => {
    if (synced || Object.keys(availability).length === 0) return;
    const updates: Partial<AppSettings> = {};
    for (const { key, cli } of backends) {
      const isAvailable = availability[cli] ?? false;
      if (!isAvailable && settings[key]) {
        (updates as Record<string, boolean>)[key] = false;
      }
    }
    if (Object.keys(updates).length > 0) {
      onUpdate({ ...settings, ...updates });
    }
    setSynced(true);
  }, [availability, synced]);

  const toggle = (key: keyof AppSettings) => {
    onUpdate({ ...settings, [key]: !settings[key] });
  };

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-zinc-200">{t("setup.aiBackends")}</h3>
      <p className="text-xs text-zinc-500">
        {t("setup.backendsDescription")}
      </p>
      <div className="space-y-1">
        {backends.map(({ key, cli, label, cloud }) => {
          const isAvailable = availability[cli] ?? false;
          return (
            <div
              key={key}
              className="flex items-center justify-between py-2 px-3 rounded-md bg-zinc-800/30"
            >
              <div className="flex items-center gap-2">
                <div className={`w-2 h-2 rounded-full ${isAvailable ? "bg-green-500" : "bg-red-500"}`} />
                <span className={`text-sm ${isAvailable ? "text-zinc-200" : "text-zinc-500"}`}>{label}</span>
                <span
                  className={`text-[10px] px-1.5 py-0.5 rounded ${cloud ? "bg-blue-500/20 text-blue-400" : "bg-zinc-700 text-zinc-400"}`}
                >
                  {cloud ? t("setup.cloud") : t("setup.local")}
                </span>
                {!isAvailable && (
                  <span className="text-[10px] text-zinc-600">{t("setup.notInstalled")}</span>
                )}
              </div>
              <button
                onClick={() => toggle(key)}
                className={`w-10 h-5 rounded-full transition-colors relative ${
                  settings[key] ? "bg-brand-600" : "bg-zinc-700"
                }`}
              >
                <div
                  className={`w-4 h-4 bg-white rounded-full absolute top-0.5 transition-transform ${
                    settings[key] ? "translate-x-5" : "translate-x-0.5"
                  }`}
                />
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
