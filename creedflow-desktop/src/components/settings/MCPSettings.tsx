import { useState } from "react";
import { Plus, Trash2, Server, ChevronDown, ChevronRight } from "lucide-react";

interface MCPServer {
  name: string;
  command: string;
  args: string[];
  env: Record<string, string>;
}

const TEMPLATES: { name: string; server: MCPServer }[] = [
  {
    name: "DALL-E (Image Generation)",
    server: {
      name: "dalle",
      command: "npx",
      args: ["-y", "@anthropic/mcp-dalle"],
      env: { OPENAI_API_KEY: "" },
    },
  },
  {
    name: "Figma (Design)",
    server: {
      name: "figma",
      command: "npx",
      args: ["-y", "@anthropic/mcp-figma"],
      env: { FIGMA_ACCESS_TOKEN: "" },
    },
  },
  {
    name: "Stability AI (Image Generation)",
    server: {
      name: "stability",
      command: "npx",
      args: ["-y", "@anthropic/mcp-stability"],
      env: { STABILITY_API_KEY: "" },
    },
  },
  {
    name: "ElevenLabs (Voice/Audio)",
    server: {
      name: "elevenlabs",
      command: "npx",
      args: ["-y", "@anthropic/mcp-elevenlabs"],
      env: { ELEVENLABS_API_KEY: "" },
    },
  },
  {
    name: "Runway (Video Generation)",
    server: {
      name: "runway",
      command: "npx",
      args: ["-y", "@anthropic/mcp-runway"],
      env: { RUNWAY_API_KEY: "" },
    },
  },
];

export function MCPSettings() {
  const [servers, setServers] = useState<MCPServer[]>([]);
  const [showTemplates, setShowTemplates] = useState(false);
  const [expandedServer, setExpandedServer] = useState<string | null>(null);

  const addFromTemplate = (template: MCPServer) => {
    if (servers.some((s) => s.name === template.name)) return;
    setServers([...servers, { ...template }]);
    setShowTemplates(false);
  };

  const removeServer = (name: string) => {
    setServers(servers.filter((s) => s.name !== name));
  };

  const updateEnv = (serverName: string, key: string, value: string) => {
    setServers(
      servers.map((s) =>
        s.name === serverName ? { ...s, env: { ...s.env, [key]: value } } : s,
      ),
    );
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Server className="w-4 h-4 text-zinc-400" />
          <h3 className="text-sm font-medium text-zinc-200">MCP Servers</h3>
        </div>
        <button
          onClick={() => setShowTemplates(!showTemplates)}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded transition-colors"
        >
          <Plus className="w-3.5 h-3.5" />
          Add Server
        </button>
      </div>

      <p className="text-xs text-zinc-500">
        MCP servers extend agent capabilities with external tool access (image
        generation, design tools, etc.).
      </p>

      {/* Quick templates */}
      {showTemplates && (
        <div className="bg-zinc-800/50 border border-zinc-700 rounded-lg p-3 space-y-1.5">
          <p className="text-xs font-medium text-zinc-400 mb-2">Quick Setup Templates</p>
          {TEMPLATES.map((t) => {
            const alreadyAdded = servers.some((s) => s.name === t.server.name);
            return (
              <button
                key={t.name}
                onClick={() => addFromTemplate(t.server)}
                disabled={alreadyAdded}
                className="w-full text-left px-3 py-2 text-xs text-zinc-300 hover:bg-zinc-700 rounded transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {t.name}
                {alreadyAdded && (
                  <span className="ml-2 text-zinc-600">(added)</span>
                )}
              </button>
            );
          })}
        </div>
      )}

      {/* Server list */}
      {servers.length === 0 ? (
        <div className="text-xs text-zinc-600 py-4 text-center">
          No MCP servers configured. Click "Add Server" to get started.
        </div>
      ) : (
        <div className="space-y-2">
          {servers.map((server) => {
            const isExpanded = expandedServer === server.name;
            return (
              <div
                key={server.name}
                className="bg-zinc-800/50 border border-zinc-800 rounded-lg overflow-hidden"
              >
                <div className="flex items-center justify-between px-3 py-2">
                  <button
                    onClick={() =>
                      setExpandedServer(isExpanded ? null : server.name)
                    }
                    className="flex items-center gap-2 text-xs text-zinc-200"
                  >
                    {isExpanded ? (
                      <ChevronDown className="w-3.5 h-3.5 text-zinc-500" />
                    ) : (
                      <ChevronRight className="w-3.5 h-3.5 text-zinc-500" />
                    )}
                    <span className="font-medium">{server.name}</span>
                    <span className="text-zinc-500 font-mono">
                      {server.command} {server.args.join(" ")}
                    </span>
                  </button>
                  <button
                    onClick={() => removeServer(server.name)}
                    className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-red-400 transition-colors"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>

                {isExpanded && Object.keys(server.env).length > 0 && (
                  <div className="px-3 pb-3 space-y-2 border-t border-zinc-800/50 pt-2">
                    <p className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
                      Environment Variables
                    </p>
                    {Object.entries(server.env).map(([key, value]) => (
                      <div key={key} className="flex items-center gap-2">
                        <span className="text-xs text-zinc-400 font-mono w-[160px] truncate">
                          {key}
                        </span>
                        <input
                          type="password"
                          value={value}
                          onChange={(e) =>
                            updateEnv(server.name, key, e.target.value)
                          }
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
    </div>
  );
}
