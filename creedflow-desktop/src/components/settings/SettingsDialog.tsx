import { useEffect } from "react";
import { useSettingsStore } from "../../store/settingsStore";
import { BackendSettings } from "./BackendSettings";
import { AgentPreferences } from "./AgentPreferences";

export function SettingsDialog() {
  const { settings, fetchSettings, updateSettings } = useSettingsStore();

  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  if (!settings) return null;

  return (
    <div className="flex-1 flex flex-col overflow-y-auto">
      <div className="px-4 py-3 border-b border-zinc-800">
        <h2 className="text-sm font-semibold text-zinc-200">Settings</h2>
      </div>

      <div className="p-4 space-y-6 max-w-2xl">
        {/* General */}
        <section>
          <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
            General
          </h3>
          <div className="space-y-3">
            <div>
              <label className="block text-xs text-zinc-400 mb-1">
                Projects Directory
              </label>
              <input
                type="text"
                value={settings.projectsDir}
                onChange={(e) =>
                  updateSettings({ ...settings, projectsDir: e.target.value })
                }
                className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs text-zinc-400 mb-1">
                  Max Concurrency
                </label>
                <input
                  type="number"
                  value={settings.maxConcurrency}
                  onChange={(e) =>
                    updateSettings({
                      ...settings,
                      maxConcurrency: parseInt(e.target.value) || 3,
                    })
                  }
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
                />
              </div>
              <div>
                <label className="block text-xs text-zinc-400 mb-1">
                  Monthly Budget (USD)
                </label>
                <input
                  type="number"
                  value={settings.monthlyBudgetUsd}
                  onChange={(e) =>
                    updateSettings({
                      ...settings,
                      monthlyBudgetUsd: parseFloat(e.target.value) || 50,
                    })
                  }
                  className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
                />
              </div>
            </div>
          </div>
        </section>

        {/* Backends */}
        <BackendSettings />

        {/* Agent Preferences */}
        <AgentPreferences />
      </div>
    </div>
  );
}
