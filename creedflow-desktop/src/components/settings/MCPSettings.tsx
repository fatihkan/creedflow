import { useEffect, useState } from "react";
import {
  Plus,
  Trash2,
  Server,
  ChevronDown,
  ChevronRight,
  ToggleLeft,
  ToggleRight,
  Pencil,
  X,
} from "lucide-react";
import type { MCPServerConfig } from "../../types/models";
import * as api from "../../tauri";
import { useErrorToast } from "../../hooks/useErrorToast";
import { FocusTrap } from "../shared/FocusTrap";

interface MCPTemplate {
  name: string;
  command: string;
  args: string;
  env: Record<string, string>;
}

const TEMPLATES: { label: string; template: MCPTemplate }[] = [
  {
    label: "DALL-E (Image Generation)",
    template: {
      name: "dalle",
      command: "npx",
      args: "-y @anthropic/mcp-dalle",
      env: { OPENAI_API_KEY: "" },
    },
  },
  {
    label: "Figma (Design)",
    template: {
      name: "figma",
      command: "npx",
      args: "-y @anthropic/mcp-figma",
      env: { FIGMA_ACCESS_TOKEN: "" },
    },
  },
  {
    label: "Stability AI (Image Generation)",
    template: {
      name: "stability",
      command: "npx",
      args: "-y @anthropic/mcp-stability",
      env: { STABILITY_API_KEY: "" },
    },
  },
  {
    label: "ElevenLabs (Voice/Audio)",
    template: {
      name: "elevenlabs",
      command: "npx",
      args: "-y @anthropic/mcp-elevenlabs",
      env: { ELEVENLABS_API_KEY: "" },
    },
  },
  {
    label: "Runway (Video Generation)",
    template: {
      name: "runway",
      command: "npx",
      args: "-y @anthropic/mcp-runway",
      env: { RUNWAY_API_KEY: "" },
    },
  },
];

function healthDot(status: string | undefined) {
  if (status === "healthy") return "bg-green-400";
  if (status === "degraded") return "bg-amber-400";
  if (status === "unhealthy") return "bg-red-400";
  return "bg-zinc-600";
}

export function MCPSettings() {
  const [servers, setServers] = useState<MCPServerConfig[]>([]);
  const [healthMap, setHealthMap] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [showTemplates, setShowTemplates] = useState(false);
  const [expandedServer, setExpandedServer] = useState<string | null>(null);
  const [editingServer, setEditingServer] = useState<MCPServerConfig | null>(null);
  const [showForm, setShowForm] = useState(false);
  const withError = useErrorToast();

  const fetchServers = async () => {
    setLoading(true);
    await withError(async () => {
      const data = await api.listMcpServers();
      setServers(data);
    });
    setLoading(false);
  };

  const fetchHealth = async () => {
    await withError(async () => {
      const events = await api.getMcpHealthStatus();
      const map: Record<string, string> = {};
      for (const e of events) {
        map[e.targetName] = e.status;
      }
      setHealthMap(map);
    });
  };

  useEffect(() => {
    fetchServers();
    fetchHealth();
  }, []);

  const addFromTemplate = async (t: MCPTemplate) => {
    if (servers.some((s) => s.name === t.name)) return;
    await withError(async () => {
      const created = await api.createMcpServer(
        t.name,
        t.command,
        t.args,
        JSON.stringify(t.env),
      );
      setServers((prev) => [...prev, created]);
    });
    setShowTemplates(false);
  };

  const handleToggle = async (server: MCPServerConfig) => {
    await withError(async () => {
      const updated = await api.updateMcpServer(
        server.id,
        server.name,
        server.command,
        server.arguments,
        server.environmentVars,
        !server.isEnabled,
      );
      setServers((prev) => prev.map((s) => (s.id === updated.id ? updated : s)));
    });
  };

  const handleDelete = async (id: string) => {
    await withError(async () => {
      await api.deleteMcpServer(id);
      setServers((prev) => prev.filter((s) => s.id !== id));
    });
  };

  const handleSaved = (server: MCPServerConfig) => {
    setServers((prev) => {
      const exists = prev.find((s) => s.id === server.id);
      if (exists) return prev.map((s) => (s.id === server.id ? server : s));
      return [...prev, server];
    });
    setShowForm(false);
    setEditingServer(null);
  };

  const updateEnv = async (server: MCPServerConfig, key: string, value: string) => {
    let envObj: Record<string, string> = {};
    try { envObj = JSON.parse(server.environmentVars); } catch { /* empty */ }
    envObj[key] = value;
    const newEnvVars = JSON.stringify(envObj);
    await withError(async () => {
      const updated = await api.updateMcpServer(
        server.id,
        server.name,
        server.command,
        server.arguments,
        newEnvVars,
        server.isEnabled,
      );
      setServers((prev) => prev.map((s) => (s.id === updated.id ? updated : s)));
    });
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Server className="w-4 h-4 text-zinc-400" />
          <h3 className="text-sm font-medium text-zinc-200">MCP Servers</h3>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowTemplates(!showTemplates)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded transition-colors"
          >
            Quick Setup
          </button>
          <button
            onClick={() => {
              setEditingServer(null);
              setShowForm(true);
            }}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded transition-colors"
          >
            <Plus className="w-3.5 h-3.5" />
            Add Server
          </button>
        </div>
      </div>

      <p className="text-xs text-zinc-500">
        MCP servers extend agent capabilities with external tool access (image
        generation, design tools, etc.). Configurations persist across restarts.
      </p>

      {/* Quick templates */}
      {showTemplates && (
        <div className="bg-zinc-800/50 border border-zinc-700 rounded-lg p-3 space-y-1.5">
          <p className="text-xs font-medium text-zinc-400 mb-2">Quick Setup Templates</p>
          {TEMPLATES.map((t) => {
            const alreadyAdded = servers.some((s) => s.name === t.template.name);
            return (
              <button
                key={t.label}
                onClick={() => addFromTemplate(t.template)}
                disabled={alreadyAdded}
                className="w-full text-left px-3 py-2 text-xs text-zinc-300 hover:bg-zinc-700 rounded transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {t.label}
                {alreadyAdded && (
                  <span className="ml-2 text-zinc-600">(added)</span>
                )}
              </button>
            );
          })}
        </div>
      )}

      {/* Server list */}
      {loading ? (
        <div className="text-xs text-zinc-500 py-4 text-center">Loading...</div>
      ) : servers.length === 0 ? (
        <div className="text-xs text-zinc-600 py-4 text-center">
          No MCP servers configured. Click "Add Server" or use Quick Setup.
        </div>
      ) : (
        <div className="space-y-2">
          {servers.map((server) => {
            const isExpanded = expandedServer === server.id;
            const status = healthMap[server.name];
            let envObj: Record<string, string> = {};
            try { envObj = JSON.parse(server.environmentVars); } catch { /* empty */ }

            return (
              <div
                key={server.id}
                className="bg-zinc-800/50 border border-zinc-800 rounded-lg overflow-hidden"
              >
                <div className="flex items-center justify-between px-3 py-2">
                  <button
                    onClick={() => setExpandedServer(isExpanded ? null : server.id)}
                    className="flex items-center gap-2 text-xs text-zinc-200 flex-1 min-w-0"
                  >
                    {isExpanded ? (
                      <ChevronDown className="w-3.5 h-3.5 text-zinc-500 flex-shrink-0" />
                    ) : (
                      <ChevronRight className="w-3.5 h-3.5 text-zinc-500 flex-shrink-0" />
                    )}
                    <span className={`w-2 h-2 rounded-full flex-shrink-0 ${healthDot(status)}`} />
                    <span className="font-medium truncate">{server.name}</span>
                    <span className="text-zinc-500 font-mono truncate">
                      {server.command} {server.arguments}
                    </span>
                  </button>
                  <div className="flex items-center gap-1 flex-shrink-0 ml-2">
                    <button
                      onClick={() => handleToggle(server)}
                      title={server.isEnabled ? "Disable" : "Enable"}
                      aria-label={server.isEnabled ? `Disable ${server.name}` : `Enable ${server.name}`}
                    >
                      {server.isEnabled ? (
                        <ToggleRight className="w-5 h-5 text-green-400" />
                      ) : (
                        <ToggleLeft className="w-5 h-5 text-zinc-500" />
                      )}
                    </button>
                    <button
                      onClick={() => {
                        setEditingServer(server);
                        setShowForm(true);
                      }}
                      className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-zinc-200 transition-colors"
                      aria-label={`Edit ${server.name}`}
                    >
                      <Pencil className="w-3.5 h-3.5" />
                    </button>
                    <button
                      onClick={() => handleDelete(server.id)}
                      className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-red-400 transition-colors"
                      aria-label={`Delete ${server.name}`}
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>

                {isExpanded && Object.keys(envObj).length > 0 && (
                  <div className="px-3 pb-3 space-y-2 border-t border-zinc-800/50 pt-2">
                    <p className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
                      Environment Variables
                    </p>
                    {Object.entries(envObj).map(([key, value]) => (
                      <div key={key} className="flex items-center gap-2">
                        <span className="text-xs text-zinc-400 font-mono w-[160px] truncate">
                          {key}
                        </span>
                        <input
                          type="password"
                          value={value}
                          onChange={(e) => {
                            // Update local state immediately, persist on blur
                            const newVal = e.target.value;
                            setServers((prev) =>
                              prev.map((s) => {
                                if (s.id !== server.id) return s;
                                const obj = { ...envObj, [key]: newVal };
                                return { ...s, environmentVars: JSON.stringify(obj) };
                              }),
                            );
                          }}
                          onBlur={(e) => updateEnv(server, key, e.target.value)}
                          placeholder="Enter value..."
                          className="flex-1 px-2 py-1 text-xs bg-zinc-900 border border-zinc-700 rounded text-zinc-300 placeholder-zinc-600 focus:outline-none focus:border-brand-500 font-mono"
                        />
                      </div>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Add/Edit modal */}
      {showForm && (
        <MCPServerFormModal
          server={editingServer}
          onClose={() => {
            setShowForm(false);
            setEditingServer(null);
          }}
          onSaved={handleSaved}
        />
      )}
    </div>
  );
}

function MCPServerFormModal({
  server,
  onClose,
  onSaved,
}: {
  server: MCPServerConfig | null;
  onClose: () => void;
  onSaved: (server: MCPServerConfig) => void;
}) {
  const isEditing = server !== null;
  const [name, setName] = useState(server?.name ?? "");
  const [command, setCommand] = useState(server?.command ?? "");
  const [args, setArgs] = useState(server?.arguments ?? "");
  const [envVars, setEnvVars] = useState(server?.environmentVars ?? "{}");
  const [saving, setSaving] = useState(false);
  const withError = useErrorToast();

  const handleSave = async () => {
    setSaving(true);
    await withError(async () => {
      let result: MCPServerConfig;
      if (isEditing) {
        result = await api.updateMcpServer(
          server.id,
          name,
          command,
          args,
          envVars,
          server.isEnabled,
        );
      } else {
        result = await api.createMcpServer(name, command, args, envVars);
      }
      onSaved(result);
    });
    setSaving(false);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" role="dialog" aria-modal="true" aria-labelledby="mcp-form-title">
      <FocusTrap>
      <div className="bg-zinc-900 border border-zinc-700 rounded-xl w-[440px] p-5 shadow-2xl">
        <div className="flex items-center justify-between mb-4">
          <h3 id="mcp-form-title" className="text-sm font-semibold text-zinc-200">
            {isEditing ? "Edit MCP Server" : "Add MCP Server"}
          </h3>
          <button onClick={onClose} className="text-zinc-500 hover:text-zinc-300" aria-label="Close dialog">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="space-y-3">
          <div>
            <label className="text-[11px] text-zinc-400 mb-1 block">Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. dalle"
              className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:border-brand-500"
            />
          </div>
          <div>
            <label className="text-[11px] text-zinc-400 mb-1 block">Command</label>
            <input
              type="text"
              value={command}
              onChange={(e) => setCommand(e.target.value)}
              placeholder="e.g. npx"
              className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:border-brand-500 font-mono"
            />
          </div>
          <div>
            <label className="text-[11px] text-zinc-400 mb-1 block">Arguments</label>
            <input
              type="text"
              value={args}
              onChange={(e) => setArgs(e.target.value)}
              placeholder="e.g. -y @anthropic/mcp-dalle"
              className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:border-brand-500 font-mono"
            />
          </div>
          <div>
            <label className="text-[11px] text-zinc-400 mb-1 block">
              Environment Variables (JSON)
            </label>
            <textarea
              value={envVars}
              onChange={(e) => setEnvVars(e.target.value)}
              placeholder='{"API_KEY": "..."}'
              rows={3}
              className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:border-brand-500 font-mono resize-none"
            />
          </div>
        </div>

        <div className="flex justify-end gap-2 mt-4">
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-xs text-zinc-400 hover:text-zinc-200 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={!name.trim() || !command.trim() || saving}
            className="px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded disabled:opacity-50 transition-colors"
          >
            {saving ? "Saving..." : isEditing ? "Update" : "Create"}
          </button>
        </div>
      </div>
      </FocusTrap>
    </div>
  );
}
