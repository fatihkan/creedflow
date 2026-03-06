import { useEffect, useState } from "react";
import {
  Download,
  Loader2,
  RefreshCw,
} from "lucide-react";
import * as api from "../../tauri";
import type { DependencyStatus } from "../../types/models";
import type { GitConfig } from "../../tauri";
import { showErrorToast } from "../../hooks/useErrorToast";

export function GitSettings() {
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
    }).catch((e) => showErrorToast("Failed to load git config", e));

    api.detectDependencies()
      .then(setDeps)
      .catch((e) => showErrorToast("Failed to detect dependencies", e))
      .finally(() => setLoadingDeps(false));
  }, []);

  const saveGit = async () => {
    setSaving(true);
    try {
      await api.setGitConfig(gitName, gitEmail);
      const gc = await api.getGitConfig();
      setGitConfig(gc);
    } catch (e) {
      showErrorToast("Failed to save git config", e);
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
      showErrorToast("Failed to install dependency", e);
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
          <span className="text-zinc-600">&rarr;</span>
          <span className="px-2 py-1 bg-yellow-500/20 text-yellow-400 rounded font-mono">staging</span>
          <span className="text-zinc-600">&rarr;</span>
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
