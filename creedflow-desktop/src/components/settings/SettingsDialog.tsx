import { useEffect, useState } from "react";
import {
  Settings,
  Cpu,
  GitBranch,
  Bell,
  Server,
  Database,
} from "lucide-react";
import { useSettingsStore } from "../../store/settingsStore";
import { BackendSettings } from "./BackendSettings";
import { AgentPreferences } from "./AgentPreferences";
import { MCPSettings } from "./MCPSettings";
import { GeneralSettings } from "./GeneralSettings";
import { GitSettings } from "./GitSettings";
import { TelegramSettings } from "./TelegramSettings";
import { DatabaseSettings } from "./DatabaseSettings";

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
        {tab === "general" && <GeneralSettings />}
        {tab === "backends" && <BackendsTab />}
        {tab === "git" && <GitSettings />}
        {tab === "telegram" && <TelegramSettings />}
        {tab === "database" && <DatabaseSettings />}
        {tab === "mcp" && <MCPSettings />}
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
