import { useEffect, useState } from "react";
import {
  Settings,
  Cpu,
  GitBranch,
  Bell,
  Server,
  Monitor,
  Download,
  Loader2,
  RefreshCw,
  AlertTriangle,
} from "lucide-react";
import { save } from "@tauri-apps/plugin-dialog";
import { useSettingsStore } from "../../store/settingsStore";
import { BackendSettings } from "./BackendSettings";
import { AgentPreferences } from "./AgentPreferences";
import { MCPSettings } from "./MCPSettings";
import { ThemeToggle } from "../shared/ThemeToggle";
import { Database } from "lucide-react";
import * as api from "../../tauri";
import { useFontStore } from "../../store/fontStore";
import type { DependencyStatus, DetectedEditor } from "../../types/models";
import type { GitConfig } from "../../tauri";
import { useTranslation } from "react-i18next";

type Tab = "general" | "backends" | "git" | "telegram" | "database" | "mcp";

const TABS: { id: Tab; label: string; icon: React.FC<{ className?: string }> }[] = [
  { id: "general", label: "General", icon: Settings },
  { id: "backends", label: "AI CLIs", icon: Cpu },
  { id: "git", label: "Git & Tools", icon: GitBranch },
  { id: "telegram", label: "Telegram", icon: Bell },
  { id: "database", label: "Database", icon: Database },
  { id: "mcp", label: "MCP", icon: Server },
];

export function SettingsDialog() {
  const [tab, setTab] = useState<Tab>("general");
  const { settings, fetchSettings } = useSettingsStore();

  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  if (!settings) return null;

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="px-4 py-3 border-b border-zinc-800">
        <h2 className="text-sm font-semibold text-zinc-200">Settings</h2>
      </div>

      {/* Tab bar */}
      <div className="flex border-b border-zinc-800 px-2">
        {TABS.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            className={`flex items-center gap-1.5 px-3 py-2 text-xs border-b-2 transition-colors ${
              tab === id
                ? "border-brand-500 text-brand-400"
                : "border-transparent text-zinc-500 hover:text-zinc-300"
            }`}
          >
            <Icon className="w-3.5 h-3.5" />
            {label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div className="flex-1 overflow-y-auto p-4 max-w-2xl">
        {tab === "general" && <GeneralTab />}
        {tab === "backends" && <BackendsTab />}
        {tab === "git" && <GitToolsTab />}
        {tab === "telegram" && <TelegramTab />}
        {tab === "database" && <DatabaseTab />}
        {tab === "mcp" && <MCPTab />}
      </div>
    </div>
  );
}

function GeneralTab() {
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
    api.detectEditors().then(setEditors).catch(console.error);
    api.getPreferredEditor().then(setPreferredEditor).catch(console.error);
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
          <option value="tr">Türkçe</option>
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

function BackendsTab() {
  return (
    <div className="space-y-6">
      <BackendSettings />
      <AgentPreferences />
    </div>
  );
}

function GitToolsTab() {
  const [gitConfig, setGitConfig] = useState<GitConfig | null>(null);
  const [gitName, setGitName] = useState("");
  const [gitEmail, setGitEmail] = useState("");
  const [saving, setSaving] = useState(false);
  const [deps, setDeps] = useState<DependencyStatus[]>([]);
  const [installing, setInstalling] = useState<string | null>(null);
  const [loadingDeps, setLoadingDeps] = useState(true);

  useEffect(() => {
    api.getGitConfig().then((gc) => {
      setGitConfig(gc);
      setGitName(gc.userName);
      setGitEmail(gc.userEmail);
    }).catch(console.error);

    api.detectDependencies()
      .then(setDeps)
      .catch(console.error)
      .finally(() => setLoadingDeps(false));
  }, []);

  const saveGit = async () => {
    setSaving(true);
    try {
      await api.setGitConfig(gitName, gitEmail);
      const gc = await api.getGitConfig();
      setGitConfig(gc);
    } catch (e) {
      console.error(e);
    } finally {
      setSaving(false);
    }
  };

  const refreshDeps = async () => {
    setLoadingDeps(true);
    try {
      const d = await api.detectDependencies();
      setDeps(d);
    } finally {
      setLoadingDeps(false);
    }
  };

  const handleInstall = async (name: string) => {
    setInstalling(name);
    try {
      await api.installDependency(name);
      const updated = await api.detectDependencies();
      setDeps(updated);
    } catch (e) {
      console.error(e);
    } finally {
      setInstalling(null);
    }
  };

  return (
    <div className="space-y-6">
      {/* Git status */}
      <section>
        <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
          Git Configuration
        </h3>
        <div className="space-y-3">
          <div className="flex items-center gap-3 text-xs">
            <div className={`w-2 h-2 rounded-full ${gitConfig?.gitInstalled ? "bg-green-500" : "bg-red-500"}`} />
            <span className="text-zinc-300">Git</span>
            <span className="text-zinc-600">{gitConfig?.gitVersion || "Not installed"}</span>
          </div>
          <div className="flex items-center gap-3 text-xs">
            <div className={`w-2 h-2 rounded-full ${gitConfig?.ghInstalled ? "bg-green-500" : "bg-red-500"}`} />
            <span className="text-zinc-300">GitHub CLI</span>
            <span className="text-zinc-600">{gitConfig?.ghVersion || "Not installed"}</span>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs text-zinc-400 mb-1">user.name</label>
              <input
                type="text"
                value={gitName}
                onChange={(e) => setGitName(e.target.value)}
                className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
              />
            </div>
            <div>
              <label className="block text-xs text-zinc-400 mb-1">user.email</label>
              <input
                type="text"
                value={gitEmail}
                onChange={(e) => setGitEmail(e.target.value)}
                className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
              />
            </div>
          </div>
          <button
            onClick={saveGit}
            disabled={saving}
            className="px-4 py-1.5 text-xs bg-brand-600 text-white rounded hover:bg-brand-700 disabled:opacity-50"
          >
            {saving ? "Saving..." : "Save Git Config"}
          </button>
        </div>
      </section>

      {/* Branching strategy */}
      <section>
        <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
          Branching Strategy
        </h3>
        <div className="flex items-center gap-2 text-xs">
          <span className="px-2 py-1 bg-blue-500/20 text-blue-400 rounded font-mono">dev</span>
          <span className="text-zinc-600">→</span>
          <span className="px-2 py-1 bg-yellow-500/20 text-yellow-400 rounded font-mono">staging</span>
          <span className="text-zinc-600">→</span>
          <span className="px-2 py-1 bg-green-500/20 text-green-400 rounded font-mono">main</span>
        </div>
        <p className="text-[10px] text-zinc-600 mt-2">
          Feature branches merge into dev via PR. Dev promotes to staging, staging to main.
        </p>
      </section>

      {/* System Dependencies */}
      <section>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">
            System Dependencies
          </h3>
          <button
            onClick={refreshDeps}
            disabled={loadingDeps}
            className="p-1 text-zinc-500 hover:text-zinc-300 rounded"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loadingDeps ? "animate-spin" : ""}`} />
          </button>
        </div>
        {loadingDeps ? (
          <div className="flex items-center gap-2 text-zinc-500 text-xs">
            <Loader2 className="w-3.5 h-3.5 animate-spin" /> Detecting...
          </div>
        ) : (
          <div className="space-y-1">
            {deps.map((dep) => (
              <div
                key={dep.name}
                className="flex items-center justify-between py-1.5 px-3 rounded bg-zinc-800/30"
              >
                <div className="flex items-center gap-2">
                  <div className={`w-2 h-2 rounded-full ${dep.installed ? "bg-green-500" : "bg-red-500"}`} />
                  <span className="text-xs text-zinc-200 font-mono">{dep.name}</span>
                  {dep.version && <span className="text-[10px] text-zinc-500">{dep.version}</span>}
                </div>
                {!dep.installed && (
                  <button
                    onClick={() => handleInstall(dep.name)}
                    disabled={installing !== null}
                    className="flex items-center gap-1 px-2 py-1 text-[10px] bg-brand-600/20 text-brand-400 rounded hover:bg-brand-600/30 disabled:opacity-50"
                  >
                    {installing === dep.name ? (
                      <Loader2 className="w-3 h-3 animate-spin" />
                    ) : (
                      <Download className="w-3 h-3" />
                    )}
                    Install
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function TelegramTab() {
  const { settings, updateSettings } = useSettingsStore();
  if (!settings) return null;

  return (
    <div className="space-y-4">
      <p className="text-xs text-zinc-500">
        Configure Telegram notifications for task milestones, deploy events, and failures.
      </p>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">Bot Token</label>
        <input
          type="password"
          value={settings.telegramBotToken ?? ""}
          onChange={(e) =>
            updateSettings({ ...settings, telegramBotToken: e.target.value || null })
          }
          placeholder="123456:ABC-DEF..."
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
        />
      </div>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">Default Chat ID</label>
        <input
          type="text"
          value={settings.telegramChatId ?? ""}
          onChange={(e) =>
            updateSettings({ ...settings, telegramChatId: e.target.value || null })
          }
          placeholder="-100123456789"
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
        />
      </div>
      <p className="text-[10px] text-zinc-600">
        Create a bot via @BotFather on Telegram. The chat ID is the group or channel where notifications will be sent.
      </p>
    </div>
  );
}

function DatabaseTab() {
  const [dbInfo, setDbInfo] = useState<api.DbInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [confirmReset, setConfirmReset] = useState(false);

  useEffect(() => {
    api.getDbInfo()
      .then(setDbInfo)
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  const handleVacuum = async () => {
    setWorking(true);
    try {
      await api.vacuumDatabase();
      setResult("Vacuum completed");
      const info = await api.getDbInfo();
      setDbInfo(info);
    } catch (e) {
      setResult(`Error: ${e}`);
    } finally {
      setWorking(false);
    }
  };

  const handlePrune = async () => {
    setWorking(true);
    try {
      const count = await api.pruneOldLogs(30);
      setResult(`Pruned ${count} log entries`);
      const info = await api.getDbInfo();
      setDbInfo(info);
    } catch (e) {
      setResult(`Error: ${e}`);
    } finally {
      setWorking(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-zinc-500 text-xs">
        <Loader2 className="w-3.5 h-3.5 animate-spin" /> Loading database info...
      </div>
    );
  }

  return (
    <div className="space-y-5">
      {dbInfo && (
        <section>
          <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
            Database Info
          </h3>
          <div className="space-y-2 text-xs">
            <div className="flex justify-between py-1.5 px-3 rounded bg-zinc-800/30">
              <span className="text-zinc-400">File Size</span>
              <span className="text-zinc-200 font-mono">{formatSize(dbInfo.sizeBytes)}</span>
            </div>
            <div className="flex justify-between py-1.5 px-3 rounded bg-zinc-800/30">
              <span className="text-zinc-400">Path</span>
              <span className="text-zinc-500 font-mono text-[10px] truncate max-w-[300px]">{dbInfo.path}</span>
            </div>
            <details className="text-xs">
              <summary className="cursor-pointer text-zinc-400 hover:text-zinc-300 py-1">
                Tables ({dbInfo.tables.length})
              </summary>
              <div className="mt-1 space-y-0.5">
                {dbInfo.tables.map((t) => (
                  <div key={t.name} className="flex justify-between py-1 px-3 rounded bg-zinc-800/20">
                    <span className="text-zinc-400 font-mono">{t.name}</span>
                    <span className="text-zinc-500">{t.rowCount} rows</span>
                  </div>
                ))}
              </div>
            </details>
          </div>
        </section>
      )}

      <section>
        <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
          Maintenance
        </h3>
        <div className="flex flex-wrap gap-2">
          <button
            onClick={handleVacuum}
            disabled={working}
            className="px-4 py-1.5 text-xs bg-zinc-800 border border-zinc-700 text-zinc-300 rounded hover:bg-zinc-700 disabled:opacity-50"
          >
            {working ? "Working..." : "Vacuum"}
          </button>
          <button
            onClick={handlePrune}
            disabled={working}
            className="px-4 py-1.5 text-xs bg-zinc-800 border border-zinc-700 text-zinc-300 rounded hover:bg-zinc-700 disabled:opacity-50"
          >
            Prune Logs (&gt; 30 days)
          </button>
          <button
            onClick={async () => {
              try {
                const path = await save({
                  defaultPath: "creedflow-export.json",
                  filters: [{ name: "JSON", extensions: ["json"] }],
                });
                if (path) {
                  setWorking(true);
                  await api.exportDatabaseJson(path);
                  setResult("Database exported to JSON");
                  setWorking(false);
                }
              } catch (e) {
                setResult(`Export error: ${e}`);
                setWorking(false);
              }
            }}
            disabled={working}
            className="flex items-center gap-1.5 px-4 py-1.5 text-xs bg-zinc-800 border border-zinc-700 text-zinc-300 rounded hover:bg-zinc-700 disabled:opacity-50"
          >
            <Download className="w-3 h-3" />
            Export JSON
          </button>
        </div>
        {result && (
          <p className="text-[10px] text-zinc-500 mt-2">{result}</p>
        )}
      </section>

      <section>
        <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
          Danger Zone
        </h3>
        {!confirmReset ? (
          <button
            onClick={() => setConfirmReset(true)}
            className="flex items-center gap-1.5 px-4 py-1.5 text-xs bg-red-900/30 border border-red-800/50 text-red-400 rounded hover:bg-red-900/50"
          >
            <AlertTriangle className="w-3 h-3" />
            Factory Reset
          </button>
        ) : (
          <div className="p-3 bg-red-950/50 border border-red-800/50 rounded-lg space-y-2">
            <p className="text-xs text-red-300 font-medium">
              This will permanently delete all projects, tasks, reviews, and data. This cannot be undone.
            </p>
            <div className="flex gap-2">
              <button
                onClick={async () => {
                  setWorking(true);
                  try {
                    await api.factoryResetDatabase();
                    setResult("Factory reset complete. All data cleared.");
                    const info = await api.getDbInfo();
                    setDbInfo(info);
                  } catch (e) {
                    setResult(`Reset error: ${e}`);
                  } finally {
                    setWorking(false);
                    setConfirmReset(false);
                  }
                }}
                disabled={working}
                className="px-4 py-1.5 text-xs bg-red-700 text-white rounded hover:bg-red-600 disabled:opacity-50"
              >
                {working ? "Resetting..." : "Confirm Reset"}
              </button>
              <button
                onClick={() => setConfirmReset(false)}
                className="px-4 py-1.5 text-xs bg-zinc-800 border border-zinc-700 text-zinc-300 rounded hover:bg-zinc-700"
              >
                Cancel
              </button>
            </div>
          </div>
        )}
      </section>
    </div>
  );
}

function MCPTab() {
  return <MCPSettings />;
}
