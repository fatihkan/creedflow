import { useEffect, useState } from "react";
import { Link2, Plus, Trash2, Edit2, Download, ExternalLink } from "lucide-react";
import type { IssueTrackingConfig, IssueMapping, IssueProvider } from "../../types/models";
import {
  listIssueConfigs,
  createIssueConfig,
  updateIssueConfig,
  deleteIssueConfig,
  importIssues,
  listIssueMappings,
} from "../../tauri";
import { listProjects } from "../../tauri";
import type { Project } from "../../types/models";

export function IntegrationsSettings() {
  const [configs, setConfigs] = useState<IssueTrackingConfig[]>([]);
  const [projects, setProjects] = useState<Project[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [editingConfig, setEditingConfig] = useState<IssueTrackingConfig | null>(null);
  const [importing, setImporting] = useState<string | null>(null);
  const [statusMsg, setStatusMsg] = useState<string | null>(null);
  const [mappings, setMappings] = useState<Record<string, IssueMapping[]>>({});

  const load = async () => {
    try {
      const [cfgs, projs] = await Promise.all([listIssueConfigs(), listProjects()]);
      setConfigs(cfgs);
      setProjects(projs);
    } catch {
      // non-fatal
    }
  };

  useEffect(() => { load(); }, []);

  const handleImport = async (configId: string) => {
    setImporting(configId);
    setStatusMsg(null);
    try {
      const result = await importIssues(configId);
      setStatusMsg(`Imported ${result.length} issues`);
      await load();
    } catch (e: unknown) {
      setStatusMsg(`Import failed: ${e instanceof Error ? e.message : String(e)}`);
    }
    setImporting(null);
  };

  const handleDelete = async (id: string) => {
    try {
      await deleteIssueConfig(id);
      await load();
    } catch {
      // non-fatal
    }
  };

  const toggleMappings = async (configId: string) => {
    if (mappings[configId]) {
      setMappings((prev) => {
        const next = { ...prev };
        delete next[configId];
        return next;
      });
    } else {
      try {
        const m = await listIssueMappings(configId);
        setMappings((prev) => ({ ...prev, [configId]: m }));
      } catch {
        // non-fatal
      }
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Link2 className="w-4 h-4 text-zinc-400" />
          <h3 className="text-sm font-semibold text-zinc-200">Issue Tracking</h3>
        </div>
        <button
          onClick={() => { setEditingConfig(null); setShowForm(true); }}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 rounded text-white"
        >
          <Plus className="w-3 h-3" />
          Add Integration
        </button>
      </div>

      {configs.length === 0 && !showForm && (
        <p className="text-xs text-zinc-500">
          No integrations configured. Add a Linear or Jira integration to import issues into CreedFlow.
        </p>
      )}

      {configs.map((config) => (
        <div key={config.id} className="bg-zinc-800/50 border border-zinc-700 rounded-lg p-4 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="text-sm font-medium text-zinc-200">{config.name}</span>
              <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full ${
                config.provider === "linear"
                  ? "bg-purple-500/15 text-purple-400"
                  : "bg-blue-500/15 text-blue-400"
              }`}>
                {config.provider.charAt(0).toUpperCase() + config.provider.slice(1)}
              </span>
              {!config.isEnabled && (
                <span className="text-[10px] text-zinc-500">Disabled</span>
              )}
              {config.syncBackEnabled && (
                <span className="text-[10px] text-green-500">Sync-back</span>
              )}
            </div>
            <div className="flex items-center gap-2">
              {config.provider === "linear" && config.isEnabled && (
                <button
                  onClick={() => handleImport(config.id)}
                  disabled={importing === config.id}
                  className="flex items-center gap-1 px-2 py-1 text-xs bg-zinc-700 hover:bg-zinc-600 rounded text-zinc-300 disabled:opacity-50"
                >
                  <Download className="w-3 h-3" />
                  {importing === config.id ? "Importing..." : "Import Now"}
                </button>
              )}
              <button
                onClick={() => toggleMappings(config.id)}
                className="px-2 py-1 text-xs bg-zinc-700 hover:bg-zinc-600 rounded text-zinc-300"
              >
                {mappings[config.id] ? "Hide" : "Show"} Issues
              </button>
              <button
                onClick={() => { setEditingConfig(config); setShowForm(true); }}
                className="p-1 text-zinc-400 hover:text-zinc-200"
              >
                <Edit2 className="w-3.5 h-3.5" />
              </button>
              <button
                onClick={() => handleDelete(config.id)}
                className="p-1 text-zinc-400 hover:text-red-400"
              >
                <Trash2 className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
          {config.lastSyncAt && (
            <p className="text-[10px] text-zinc-500">Last sync: {new Date(config.lastSyncAt).toLocaleString()}</p>
          )}
          {mappings[config.id] && (
            <div className="mt-2 space-y-1">
              {mappings[config.id].length === 0 ? (
                <p className="text-xs text-zinc-500">No imported issues</p>
              ) : (
                mappings[config.id].map((m) => (
                  <div key={m.id} className="flex items-center gap-2 text-xs text-zinc-400">
                    <span className="font-mono text-zinc-300">{m.externalIdentifier}</span>
                    <span className={`text-[10px] px-1.5 py-0.5 rounded ${
                      m.syncStatus === "synced"
                        ? "bg-green-500/15 text-green-400"
                        : m.syncStatus === "sync_failed"
                        ? "bg-red-500/15 text-red-400"
                        : "bg-zinc-600/50 text-zinc-400"
                    }`}>
                      {m.syncStatus}
                    </span>
                    {m.externalUrl && (
                      <a
                        href={m.externalUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-zinc-500 hover:text-zinc-300"
                      >
                        <ExternalLink className="w-3 h-3" />
                      </a>
                    )}
                  </div>
                ))
              )}
            </div>
          )}
        </div>
      ))}

      {/* Jira notice */}
      <div className="bg-zinc-800/30 border border-zinc-700/50 rounded-lg p-3 flex items-center gap-2">
        <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-orange-500/15 text-orange-400">
          Coming Soon
        </span>
        <span className="text-xs text-zinc-400">Jira integration is planned for a future release</span>
      </div>

      {statusMsg && (
        <p className="text-xs text-zinc-400">{statusMsg}</p>
      )}

      {showForm && (
        <ConfigForm
          config={editingConfig}
          projects={projects}
          onSave={async () => {
            setShowForm(false);
            setEditingConfig(null);
            await load();
          }}
          onCancel={() => {
            setShowForm(false);
            setEditingConfig(null);
          }}
        />
      )}
    </div>
  );
}

function ConfigForm({
  config,
  projects,
  onSave,
  onCancel,
}: {
  config: IssueTrackingConfig | null;
  projects: Project[];
  onSave: () => Promise<void>;
  onCancel: () => void;
}) {
  const [name, setName] = useState(config?.name ?? "");
  const [provider, setProvider] = useState<IssueProvider>(config?.provider ?? "linear");
  const [projectId, setProjectId] = useState(config?.projectId ?? "");
  const [apiKey, setApiKey] = useState("");
  const [teamId, setTeamId] = useState("");
  const [doneStateId, setDoneStateId] = useState("");
  const [syncBack, setSyncBack] = useState(config?.syncBackEnabled ?? false);
  const [isEnabled, setIsEnabled] = useState(config?.isEnabled ?? true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (config) {
      try {
        const creds = JSON.parse(config.credentialsJson || "{}");
        setApiKey(creds.apiKey ?? "");
        const cfg = JSON.parse(config.configJson || "{}");
        setTeamId(cfg.teamId ?? "");
        setDoneStateId(cfg.doneStateId ?? "");
      } catch {
        // ignore parse errors
      }
    }
  }, [config]);

  const handleSave = async () => {
    const credentialsJson = provider === "linear"
      ? JSON.stringify({ apiKey })
      : "{}";
    const configJson = provider === "linear"
      ? JSON.stringify({
          teamId: teamId || undefined,
          doneStateId: doneStateId || undefined,
          stateFilter: ["Todo", "In Progress"],
          agentType: "coder",
        })
      : "{}";

    try {
      if (config) {
        await updateIssueConfig(
          config.id, projectId, provider, name,
          credentialsJson, configJson, isEnabled, syncBack
        );
      } else {
        await createIssueConfig(
          projectId, provider, name,
          credentialsJson, configJson, syncBack
        );
      }
      await onSave();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  return (
    <div className="bg-zinc-800/70 border border-zinc-700 rounded-lg p-4 space-y-3">
      <h4 className="text-sm font-semibold text-zinc-200">
        {config ? "Edit Integration" : "Add Integration"}
      </h4>

      <div className="space-y-2">
        <label className="block text-xs text-zinc-400">
          Provider
          <select
            value={provider}
            onChange={(e) => setProvider(e.target.value as IssueProvider)}
            className="mt-1 block w-full px-2 py-1.5 text-xs bg-zinc-900 border border-zinc-700 rounded text-zinc-200"
          >
            <option value="linear">Linear</option>
            <option value="jira">Jira (Coming Soon)</option>
          </select>
        </label>

        <label className="block text-xs text-zinc-400">
          Name
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="My Linear Integration"
            className="mt-1 block w-full px-2 py-1.5 text-xs bg-zinc-900 border border-zinc-700 rounded text-zinc-200"
          />
        </label>

        <label className="block text-xs text-zinc-400">
          Project
          <select
            value={projectId}
            onChange={(e) => setProjectId(e.target.value)}
            className="mt-1 block w-full px-2 py-1.5 text-xs bg-zinc-900 border border-zinc-700 rounded text-zinc-200"
          >
            <option value="">Select a project...</option>
            {projects.map((p) => (
              <option key={p.id} value={p.id}>{p.name}</option>
            ))}
          </select>
        </label>

        {provider === "linear" && (
          <>
            <label className="block text-xs text-zinc-400">
              API Key
              <input
                type="password"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                placeholder="lin_api_..."
                className="mt-1 block w-full px-2 py-1.5 text-xs bg-zinc-900 border border-zinc-700 rounded text-zinc-200"
              />
            </label>
            <label className="block text-xs text-zinc-400">
              Team ID (optional)
              <input
                value={teamId}
                onChange={(e) => setTeamId(e.target.value)}
                className="mt-1 block w-full px-2 py-1.5 text-xs bg-zinc-900 border border-zinc-700 rounded text-zinc-200"
              />
            </label>
            <label className="block text-xs text-zinc-400">
              Done State ID (for sync-back)
              <input
                value={doneStateId}
                onChange={(e) => setDoneStateId(e.target.value)}
                className="mt-1 block w-full px-2 py-1.5 text-xs bg-zinc-900 border border-zinc-700 rounded text-zinc-200"
              />
            </label>
          </>
        )}

        {provider === "jira" && (
          <p className="text-xs text-orange-400">Jira integration is coming soon</p>
        )}

        <div className="flex items-center gap-4">
          <label className="flex items-center gap-2 text-xs text-zinc-400">
            <input type="checkbox" checked={isEnabled} onChange={(e) => setIsEnabled(e.target.checked)} />
            Enabled
          </label>
          <label className="flex items-center gap-2 text-xs text-zinc-400">
            <input type="checkbox" checked={syncBack} onChange={(e) => setSyncBack(e.target.checked)} />
            Sync status back
          </label>
        </div>

        {error && <p className="text-xs text-red-400">{error}</p>}
      </div>

      <div className="flex items-center justify-end gap-2">
        <button
          onClick={onCancel}
          className="px-3 py-1.5 text-xs bg-zinc-700 hover:bg-zinc-600 rounded text-zinc-300"
        >
          Cancel
        </button>
        <button
          onClick={handleSave}
          disabled={!name || !projectId || (provider === "linear" && !apiKey)}
          className="px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 rounded text-white disabled:opacity-50"
        >
          {config ? "Save" : "Add"}
        </button>
      </div>
    </div>
  );
}
