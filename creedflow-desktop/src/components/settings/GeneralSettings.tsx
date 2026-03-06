import { useEffect, useState } from "react";
import { Monitor } from "lucide-react";
import { useSettingsStore } from "../../store/settingsStore";
import { ThemeToggle } from "../shared/ThemeToggle";
import * as api from "../../tauri";
import { useFontStore } from "../../store/fontStore";
import type { DetectedEditor } from "../../types/models";
import { useTranslation } from "react-i18next";
import { showErrorToast } from "../../hooks/useErrorToast";

export function GeneralSettings() {
  const { settings, updateSettings } = useSettingsStore();
  const [editors, setEditors] = useState<DetectedEditor[]>([]);
  const [preferredEditor, setPreferredEditor] = useState<string | null>(null);
  const fontSize = useFontStore((s) => s.size);
  const setFontSize = useFontStore((s) => s.setSize);
  const { t, i18n } = useTranslation();

  const handleLanguageChange = (lng: string) => {
    i18n.changeLanguage(lng);
    localStorage.setItem("creedflow-language", lng);
    updateSettings({ ...settings!, language: lng });
  };

  useEffect(() => {
    api.detectEditors().then(setEditors).catch((e) => showErrorToast("Failed to detect editors", e));
    api.getPreferredEditor().then(setPreferredEditor).catch((e) => showErrorToast("Failed to get preferred editor", e));
  }, []);

  if (!settings) return null;

  const handleEditorChange = async (cmd: string) => {
    const value = cmd === "" ? null : cmd;
    setPreferredEditor(value);
    await api.setPreferredEditor(value);
  };

  return (
    <div className="space-y-5">
      <div>
        <label className="block text-xs text-zinc-400 mb-2">Appearance</label>
        <ThemeToggle />
      </div>

      <div>
        <label className="block text-xs text-zinc-400 mb-2">Text Size</label>
        <div className="flex gap-1">
          {(["small", "normal", "large"] as const).map((s) => (
            <button
              key={s}
              onClick={() => setFontSize(s)}
              className={`px-3 py-1.5 text-xs rounded border transition-colors ${
                fontSize === s
                  ? "bg-brand-600/20 border-brand-500 text-brand-400"
                  : "bg-zinc-800 border-zinc-700 text-zinc-400 hover:text-zinc-200"
              }`}
            >
              {s === "small" ? "Small" : s === "normal" ? "Normal" : "Large"}
            </button>
          ))}
        </div>
      </div>

      <div>
        <label className="block text-xs text-zinc-400 mb-2">{t("settings.general.language")}</label>
        <select
          value={i18n.language}
          onChange={(e) => handleLanguageChange(e.target.value)}
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
        >
          <option value="en">English</option>
          <option value="tr">Turkce</option>
        </select>
      </div>

      <div>
        <label className="block text-xs text-zinc-400 mb-1">Projects Directory</label>
        <input
          type="text"
          value={settings.projectsDir}
          onChange={(e) => updateSettings({ ...settings, projectsDir: e.target.value })}
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
        />
      </div>

      <div>
        <label className="block text-xs text-zinc-400 mb-1">Max Parallel Agents</label>
        <input
          type="number"
          min={1}
          max={8}
          value={settings.maxConcurrency}
          onChange={(e) =>
            updateSettings({ ...settings, maxConcurrency: parseInt(e.target.value) || 3 })
          }
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
        />
      </div>

      <div>
        <label className="block text-xs text-zinc-400 mb-1 flex items-center gap-1.5">
          <Monitor className="w-3.5 h-3.5" /> Preferred Editor
        </label>
        <select
          value={preferredEditor ?? ""}
          onChange={(e) => handleEditorChange(e.target.value)}
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
        >
          <option value="">Auto-detect</option>
          {editors.map((e) => (
            <option key={e.command} value={e.command}>
              {e.name}
            </option>
          ))}
        </select>
      </div>

      {/* Webhook Server */}
      <div>
        <label className="block text-xs text-zinc-400 mb-2">Webhook Server</label>
        <div className="space-y-3">
          <label className="flex items-center gap-2 text-xs text-zinc-300 cursor-pointer">
            <input
              type="checkbox"
              checked={settings.webhookEnabled ?? false}
              onChange={(e) =>
                updateSettings({ ...settings, webhookEnabled: e.target.checked })
              }
              className="rounded border-zinc-600"
            />
            Enable webhook server
          </label>
          {settings.webhookEnabled && (
            <>
              <div>
                <label className="block text-[10px] text-zinc-500 mb-1">Port</label>
                <input
                  type="number"
                  min={1024}
                  max={65535}
                  value={settings.webhookPort ?? 8080}
                  onChange={(e) =>
                    updateSettings({
                      ...settings,
                      webhookPort: parseInt(e.target.value) || 8080,
                    })
                  }
                  className="w-32 px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
                />
              </div>
              <div>
                <label className="block text-[10px] text-zinc-500 mb-1">API Key (optional)</label>
                <input
                  type="password"
                  value={settings.webhookApiKey ?? ""}
                  onChange={(e) =>
                    updateSettings({
                      ...settings,
                      webhookApiKey: e.target.value || null,
                    })
                  }
                  placeholder="Leave empty for no auth"
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
                />
              </div>
              <div>
                <label className="block text-[10px] text-zinc-500 mb-1">GitHub Webhook Secret (optional)</label>
                <input
                  type="password"
                  value={settings.webhookGithubSecret ?? ""}
                  onChange={(e) =>
                    updateSettings({
                      ...settings,
                      webhookGithubSecret: e.target.value || null,
                    })
                  }
                  placeholder="Used for X-Hub-Signature-256 validation"
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
                />
              </div>
              <p className="text-[10px] text-zinc-600">
                POST /api/tasks to create tasks via webhook. POST /api/webhooks/github for GitHub events. Requires app restart to take effect.
              </p>
            </>
          )}
        </div>
      </div>

      <div className="pt-2">
        <button
          onClick={() => updateSettings({ ...settings, hasCompletedSetup: false })}
          className="text-xs text-zinc-500 hover:text-zinc-300 underline"
        >
          Re-run Setup Wizard
        </button>
      </div>
    </div>
  );
}
