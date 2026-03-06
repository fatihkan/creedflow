import { useEffect, useState } from "react";
import { Loader2, Monitor, GitBranch } from "lucide-react";
import * as api from "../../tauri";
import type { BackendInfo, DetectedEditor } from "../../types/models";
import type { GitConfig } from "../../tauri";
import { useTranslation } from "react-i18next";
import { showErrorToast } from "../../hooks/useErrorToast";

export function EnvironmentStep() {
  const { t } = useTranslation();
  const [gitConfig, setGitConfig] = useState<GitConfig | null>(null);
  const [editors, setEditors] = useState<DetectedEditor[]>([]);
  const [preferredEditor, setPreferredEditor] = useState<string | null>(null);
  const [backends, setBackends] = useState<BackendInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [gitName, setGitName] = useState("");
  const [gitEmail, setGitEmail] = useState("");
  const [savingGit, setSavingGit] = useState(false);

  useEffect(() => {
    Promise.all([
      api.getGitConfig(),
      api.detectEditors(),
      api.getPreferredEditor(),
      api.listBackends(),
    ])
      .then(([gc, eds, pref, bk]) => {
        setGitConfig(gc);
        setGitName(gc.userName);
        setGitEmail(gc.userEmail);
        setEditors(eds);
        setPreferredEditor(pref);
        setBackends(bk);
      })
      .catch((e) => showErrorToast("Failed to detect environment", e))
      .finally(() => setLoading(false));
  }, []);

  const saveGitConfig = async () => {
    setSavingGit(true);
    try {
      await api.setGitConfig(gitName, gitEmail);
      const gc = await api.getGitConfig();
      setGitConfig(gc);
    } catch (e) {
      showErrorToast("Failed to save git config", e);
    } finally {
      setSavingGit(false);
    }
  };

  const handleEditorChange = async (cmd: string) => {
    const value = cmd === "" ? null : cmd;
    setPreferredEditor(value);
    await api.setPreferredEditor(value);
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-zinc-500 text-sm justify-center py-8">
        <Loader2 className="w-4 h-4 animate-spin" /> {t("setup.detecting")}
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <h3 className="text-lg font-semibold text-zinc-200">
        {t("setup.envDetection")}
      </h3>

      {/* AI CLIs */}
      <div>
        <p className="text-xs text-zinc-400 mb-2 font-medium">{t("setup.aiCliBackends")}</p>
        <div className="grid grid-cols-2 gap-1.5">
          {backends.map((b) => (
            <div key={b.backendType} className="flex items-center gap-2 py-1.5 px-3 rounded bg-zinc-800/30">
              <div
                className={`w-2 h-2 rounded-full ${b.isAvailable ? "bg-green-500" : "bg-red-500"}`}
              />
              <span className="text-xs text-zinc-200">{b.displayName}</span>
              {b.cliPath && (
                <span className="text-[10px] text-zinc-600 truncate ml-auto">{b.cliPath}</span>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Git */}
      <div>
        <p className="text-xs text-zinc-400 mb-2 font-medium flex items-center gap-1.5">
          <GitBranch className="w-3.5 h-3.5" /> {t("setup.gitConfiguration")}
        </p>
        <div className="space-y-2 bg-zinc-800/30 rounded-lg p-3">
          <div className="flex items-center gap-2 text-xs">
            <div className={`w-2 h-2 rounded-full ${gitConfig?.gitInstalled ? "bg-green-500" : "bg-red-500"}`} />
            <span className="text-zinc-300">Git</span>
            {gitConfig?.gitVersion && (
              <span className="text-zinc-600">{gitConfig.gitVersion}</span>
            )}
          </div>
          <div className="flex items-center gap-2 text-xs">
            <div className={`w-2 h-2 rounded-full ${gitConfig?.ghInstalled ? "bg-green-500" : "bg-red-500"}`} />
            <span className="text-zinc-300">GitHub CLI</span>
            {gitConfig?.ghVersion && (
              <span className="text-zinc-600">{gitConfig.ghVersion}</span>
            )}
          </div>
          <div className="grid grid-cols-2 gap-2 mt-2">
            <input
              type="text"
              value={gitName}
              onChange={(e) => setGitName(e.target.value)}
              placeholder="user.name"
              className="px-2 py-1.5 bg-zinc-900 border border-zinc-700 rounded text-xs text-zinc-300 placeholder:text-zinc-600"
            />
            <input
              type="text"
              value={gitEmail}
              onChange={(e) => setGitEmail(e.target.value)}
              placeholder="user.email"
              className="px-2 py-1.5 bg-zinc-900 border border-zinc-700 rounded text-xs text-zinc-300 placeholder:text-zinc-600"
            />
          </div>
          {(gitName !== (gitConfig?.userName ?? "") || gitEmail !== (gitConfig?.userEmail ?? "")) && (
            <button
              onClick={saveGitConfig}
              disabled={savingGit}
              className="text-[10px] px-3 py-1 bg-brand-600/20 text-brand-400 rounded hover:bg-brand-600/30 disabled:opacity-50"
            >
              {savingGit ? t("setup.savingGit") : t("setup.saveGitConfig")}
            </button>
          )}
        </div>
      </div>

      {/* Editor */}
      <div>
        <p className="text-xs text-zinc-400 mb-2 font-medium flex items-center gap-1.5">
          <Monitor className="w-3.5 h-3.5" /> {t("setup.codeEditor")}
        </p>
        {editors.length > 0 ? (
          <select
            value={preferredEditor ?? ""}
            onChange={(e) => handleEditorChange(e.target.value)}
            className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-xs text-zinc-300"
          >
            <option value="">{t("setup.autoDetect")}</option>
            {editors.map((e) => (
              <option key={e.command} value={e.command}>
                {e.name} — {e.path}
              </option>
            ))}
          </select>
        ) : (
          <p className="text-xs text-zinc-600">{t("setup.noEditorsDetected")}</p>
        )}
      </div>
    </div>
  );
}
