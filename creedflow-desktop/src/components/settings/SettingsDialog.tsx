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
} from "lucide-react";
import { useSettingsStore } from "../../store/settingsStore";
import { BackendSettings } from "./BackendSettings";
import { AgentPreferences } from "./AgentPreferences";
import { MCPSettings } from "./MCPSettings";
import { ThemeToggle } from "../shared/ThemeToggle";
import * as api from "../../tauri";
import type { DependencyStatus, DetectedEditor } from "../../types/models";
import type { GitConfig } from "../../tauri";

type Tab = "general" | "backends" | "git" | "telegram" | "mcp";

const TABS: { id: Tab; label: string; icon: React.FC<{ className?: string }> }[] = [
  { id: "general", label: "General", icon: Settings },
  { id: "backends", label: "AI CLIs", icon: Cpu },
  { id: "git", label: "Git & Tools", icon: GitBranch },
  { id: "telegram", label: "Telegram", icon: Bell },
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
        {tab === "mcp" && <MCPTab />}
      </div>
    </div>
  );
}

function GeneralTab() {
  const { settings, updateSettings } = useSettingsStore();
  const [editors, setEditors] = useState<DetectedEditor[]>([]);
  const [preferredEditor, setPreferredEditor] = useState<string | null>(null);

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

function MCPTab() {
  return <MCPSettings />;
}
