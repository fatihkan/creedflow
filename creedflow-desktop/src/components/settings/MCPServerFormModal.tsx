import { useState } from "react";
import { X } from "lucide-react";
import type { MCPServerConfig } from "../../types/models";
import * as api from "../../tauri";
import { useErrorToast } from "../../hooks/useErrorToast";
import { FocusTrap } from "../shared/FocusTrap";

interface MCPServerFormModalProps {
  server: MCPServerConfig | null;
  onClose: () => void;
  onSaved: (server: MCPServerConfig) => void;
}

export function MCPServerFormModal({ server, onClose, onSaved }: MCPServerFormModalProps) {
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
