import { useEffect, useState } from "react";
import {
  ArrowRight,
  ArrowLeft,
  Check,
  Download,
  Loader2,
  Zap,
  Monitor,
  GitBranch,
} from "lucide-react";
import * as api from "../../tauri";
import { useSettingsStore } from "../../store/settingsStore";
import type { AppSettings, BackendInfo, DependencyStatus, DetectedEditor } from "../../types/models";
import type { GitConfig } from "../../tauri";
import { useTranslation } from "react-i18next";

type Step = 0 | 1 | 2 | 3 | 4 | 5 | 6;

const STEP_KEYS = [
  "setup.welcome",
  "setup.environment",
  "setup.dependencies",
  "setup.backends",
  "setup.projectSettings",
  "setup.notifications",
  "setup.complete",
];

export function SetupWizard() {
  const { t } = useTranslation();
  const [step, setStep] = useState<Step>(0);
  const { settings, fetchSettings, updateSettings } = useSettingsStore();

  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  if (!settings) return null;

  const next = () => setStep((step + 1) as Step);
  const prev = () => setStep((step - 1) as Step);

  const finish = async () => {
    await updateSettings({ ...settings, hasCompletedSetup: true });
  };

  return (
    <div className="h-screen w-screen flex flex-col items-center justify-center bg-zinc-950">
      {/* Progress bar */}
      <div className="w-full max-w-2xl mb-8">
        <div className="flex items-center justify-between mb-2">
          {STEP_KEYS.map((key, i) => (
            <div key={key} className="flex items-center">
              <div
                className={`w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-bold ${
                  i < step
                    ? "bg-brand-600 text-white"
                    : i === step
                      ? "bg-brand-600/30 text-brand-400 ring-2 ring-brand-600"
                      : "bg-zinc-800 text-zinc-600"
                }`}
              >
                {i < step ? <Check className="w-3 h-3" /> : i + 1}
              </div>
              {i < STEP_KEYS.length - 1 && (
                <div
                  className={`w-6 h-0.5 mx-0.5 ${i < step ? "bg-brand-600" : "bg-zinc-800"}`}
                />
              )}
            </div>
          ))}
        </div>
        <p className="text-xs text-zinc-500 text-center">
          {t(STEP_KEYS[step])}
        </p>
      </div>

      {/* Content card */}
      <div className="w-full max-w-2xl bg-zinc-900/50 border border-zinc-800 rounded-xl p-8 min-h-[440px] flex flex-col">
        <div className="flex-1 overflow-y-auto">
          {step === 0 && <WelcomeStep />}
          {step === 1 && <EnvironmentStep />}
          {step === 2 && <DependenciesStep />}
          {step === 3 && <BackendsStep settings={settings} onUpdate={updateSettings} />}
          {step === 4 && <ProjectSettingsStep settings={settings} onUpdate={updateSettings} />}
          {step === 5 && <NotificationsStep settings={settings} onUpdate={updateSettings} />}
          {step === 6 && <CompleteStep />}
        </div>

        {/* Navigation */}
        <div className="flex items-center justify-between mt-6 pt-4 border-t border-zinc-800">
          {step > 0 && step < 6 ? (
            <button
              onClick={prev}
              className="flex items-center gap-1.5 px-4 py-2 text-sm text-zinc-400 hover:text-zinc-200"
            >
              <ArrowLeft className="w-4 h-4" /> {t("setup.back")}
            </button>
          ) : (
            <div />
          )}
          {step < 6 ? (
            <button
              onClick={next}
              className="flex items-center gap-1.5 px-4 py-2 text-sm bg-brand-600 text-white rounded-md hover:bg-brand-700"
            >
              {step === 0 ? t("setup.getStarted") : t("setup.next")}{" "}
              <ArrowRight className="w-4 h-4" />
            </button>
          ) : (
            <button
              onClick={finish}
              className="flex items-center gap-1.5 px-6 py-2 text-sm bg-brand-600 text-white rounded-md hover:bg-brand-700"
            >
              <Zap className="w-4 h-4" /> {t("setup.launch")}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function WelcomeStep() {
  const { t } = useTranslation();
  return (
    <div className="text-center space-y-4">
      <h2 className="text-2xl font-bold text-zinc-100">
        {t("setup.welcomeTitle")}
      </h2>
      <p className="text-sm text-zinc-400 max-w-sm mx-auto">
        {t("setup.welcomeDescription")}
      </p>
      <div className="text-brand-400 text-4xl font-bold tracking-wider mt-6">
        CF
      </div>
    </div>
  );
}

function EnvironmentStep() {
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
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  const saveGitConfig = async () => {
    setSavingGit(true);
    try {
      await api.setGitConfig(gitName, gitEmail);
      const gc = await api.getGitConfig();
      setGitConfig(gc);
    } catch (e) {
      console.error(e);
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

function DependenciesStep() {
  const { t } = useTranslation();
  const [deps, setDeps] = useState<DependencyStatus[]>([]);
  const [installing, setInstalling] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api
      .detectDependencies()
      .then(setDeps)
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  const handleInstall = async (name: string) => {
    setInstalling(name);
    try {
      await api.installDependency(name);
      const updated = await api.detectDependencies();
      setDeps(updated);
    } catch (e) {
      console.error("Install failed:", e);
    } finally {
      setInstalling(null);
    }
  };

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-zinc-200">
        {t("setup.systemDependencies")}
      </h3>
      <p className="text-xs text-zinc-500">
        {t("setup.dependenciesDescription")}
      </p>
      {loading ? (
        <div className="flex items-center gap-2 text-zinc-500 text-sm">
          <Loader2 className="w-4 h-4 animate-spin" /> {t("setup.detectingDeps")}
        </div>
      ) : (
        <div className="space-y-1">
          {deps.map((dep) => (
            <div
              key={dep.name}
              className="flex items-center justify-between py-2 px-3 rounded-md bg-zinc-800/30"
            >
              <div className="flex items-center gap-2">
                <div
                  className={`w-2 h-2 rounded-full ${dep.installed ? "bg-green-500" : "bg-red-500"}`}
                />
                <span className="text-sm text-zinc-200 font-mono">
                  {dep.name}
                </span>
                {dep.version && (
                  <span className="text-[10px] text-zinc-500">
                    {dep.version}
                  </span>
                )}
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
                  {t("setup.install")}
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function BackendsStep({
  settings,
  onUpdate,
}: {
  settings: AppSettings;
  onUpdate: (s: AppSettings) => Promise<void>;
}) {
  const { t } = useTranslation();
  const [availability, setAvailability] = useState<Record<string, boolean>>({});
  const [synced, setSynced] = useState(false);

  const backends = [
    { key: "claudeEnabled" as const, cli: "claude", label: "Claude", cloud: true },
    { key: "codexEnabled" as const, cli: "codex", label: "Codex", cloud: true },
    { key: "geminiEnabled" as const, cli: "gemini", label: "Gemini", cloud: true },
    { key: "opencodeEnabled" as const, cli: "opencode", label: "OpenCode", cloud: true },
    { key: "ollamaEnabled" as const, cli: "ollama", label: "Ollama", cloud: false },
    { key: "lmStudioEnabled" as const, cli: "lmStudio", label: "LM Studio", cloud: false },
    { key: "llamaCppEnabled" as const, cli: "llamaCpp", label: "llama.cpp", cloud: false },
    { key: "mlxEnabled" as const, cli: "mlx", label: "MLX", cloud: false },
  ];

  useEffect(() => {
    api.listBackends().then((infos) => {
      const avail: Record<string, boolean> = {};
      for (const info of infos) {
        avail[info.backendType] = info.isAvailable;
      }
      setAvailability(avail);
    }).catch(console.error);
  }, []);

  // Auto-sync enabled state based on availability (once)
  useEffect(() => {
    if (synced || Object.keys(availability).length === 0) return;
    const updates: Partial<AppSettings> = {};
    for (const { key, cli } of backends) {
      const isAvailable = availability[cli] ?? false;
      if (!isAvailable && settings[key]) {
        (updates as Record<string, boolean>)[key] = false;
      }
    }
    if (Object.keys(updates).length > 0) {
      onUpdate({ ...settings, ...updates });
    }
    setSynced(true);
  }, [availability, synced]);

  const toggle = (key: keyof AppSettings) => {
    onUpdate({ ...settings, [key]: !settings[key] });
  };

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-zinc-200">{t("setup.aiBackends")}</h3>
      <p className="text-xs text-zinc-500">
        {t("setup.backendsDescription")}
      </p>
      <div className="space-y-1">
        {backends.map(({ key, cli, label, cloud }) => {
          const isAvailable = availability[cli] ?? false;
          return (
            <div
              key={key}
              className="flex items-center justify-between py-2 px-3 rounded-md bg-zinc-800/30"
            >
              <div className="flex items-center gap-2">
                <div className={`w-2 h-2 rounded-full ${isAvailable ? "bg-green-500" : "bg-red-500"}`} />
                <span className={`text-sm ${isAvailable ? "text-zinc-200" : "text-zinc-500"}`}>{label}</span>
                <span
                  className={`text-[10px] px-1.5 py-0.5 rounded ${cloud ? "bg-blue-500/20 text-blue-400" : "bg-zinc-700 text-zinc-400"}`}
                >
                  {cloud ? t("setup.cloud") : t("setup.local")}
                </span>
                {!isAvailable && (
                  <span className="text-[10px] text-zinc-600">{t("setup.notInstalled")}</span>
                )}
              </div>
              <button
                onClick={() => toggle(key)}
                className={`w-10 h-5 rounded-full transition-colors relative ${
                  settings[key] ? "bg-brand-600" : "bg-zinc-700"
                }`}
              >
                <div
                  className={`w-4 h-4 bg-white rounded-full absolute top-0.5 transition-transform ${
                    settings[key] ? "translate-x-5" : "translate-x-0.5"
                  }`}
                />
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function ProjectSettingsStep({
  settings,
  onUpdate,
}: {
  settings: AppSettings;
  onUpdate: (s: AppSettings) => Promise<void>;
}) {
  const { t } = useTranslation();
  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-zinc-200">{t("setup.projectSettings")}</h3>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">
          {t("setup.projectsDir")}
        </label>
        <input
          type="text"
          value={settings.projectsDir}
          onChange={(e) => onUpdate({ ...settings, projectsDir: e.target.value })}
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
        />
      </div>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">
          {t("setup.maxConcurrency")}
        </label>
        <input
          type="number"
          value={settings.maxConcurrency}
          onChange={(e) =>
            onUpdate({
              ...settings,
              maxConcurrency: parseInt(e.target.value) || 3,
            })
          }
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
        />
      </div>
    </div>
  );
}

function NotificationsStep({
  settings,
  onUpdate,
}: {
  settings: AppSettings;
  onUpdate: (s: AppSettings) => Promise<void>;
}) {
  const { t } = useTranslation();
  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-zinc-200">{t("setup.notifications")}</h3>
      <p className="text-xs text-zinc-500">
        {t("setup.notificationsDescription")}
      </p>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">
          {t("setup.botToken")}
        </label>
        <input
          type="text"
          value={settings.telegramBotToken ?? ""}
          onChange={(e) =>
            onUpdate({
              ...settings,
              telegramBotToken: e.target.value || null,
            })
          }
          placeholder="123456:ABC..."
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
        />
      </div>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">
          {t("setup.chatId")}
        </label>
        <input
          type="text"
          value={settings.telegramChatId ?? ""}
          onChange={(e) =>
            onUpdate({
              ...settings,
              telegramChatId: e.target.value || null,
            })
          }
          placeholder="-100123456789"
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
        />
      </div>
    </div>
  );
}

function CompleteStep() {
  const { t } = useTranslation();
  return (
    <div className="text-center space-y-4">
      <div className="w-16 h-16 bg-green-500/20 rounded-full flex items-center justify-center mx-auto">
        <Check className="w-8 h-8 text-green-400" />
      </div>
      <h3 className="text-lg font-semibold text-zinc-200">{t("setup.allSet")}</h3>
      <p className="text-sm text-zinc-400 max-w-sm mx-auto">
        {t("setup.completeDescription")}
      </p>
    </div>
  );
}
