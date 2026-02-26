import { useEffect, useState } from "react";
import {
  ArrowRight,
  ArrowLeft,
  Check,
  Download,
  Loader2,
  Zap,
} from "lucide-react";
import * as api from "../../tauri";
import { useSettingsStore } from "../../store/settingsStore";
import type { AppSettings, DependencyStatus } from "../../types/models";

type Step = 0 | 1 | 2 | 3 | 4 | 5;

const STEP_LABELS = [
  "Welcome",
  "Dependencies",
  "Backends",
  "Project Directory",
  "Notifications",
  "Complete",
];

export function SetupWizard() {
  const [step, setStep] = useState<Step>(0);
  const { settings, fetchSettings, updateSettings } = useSettingsStore();

  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  if (!settings) return null;

  const next = () => setStep(((step + 1) as Step));
  const prev = () => setStep(((step - 1) as Step));

  const finish = async () => {
    await updateSettings({ ...settings, hasCompletedSetup: true });
  };

  return (
    <div className="h-screen w-screen flex flex-col items-center justify-center bg-zinc-950">
      {/* Progress bar */}
      <div className="w-full max-w-xl mb-8">
        <div className="flex items-center justify-between mb-2">
          {STEP_LABELS.map((label, i) => (
            <div key={label} className="flex items-center">
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
              {i < STEP_LABELS.length - 1 && (
                <div
                  className={`w-8 h-0.5 mx-1 ${i < step ? "bg-brand-600" : "bg-zinc-800"}`}
                />
              )}
            </div>
          ))}
        </div>
        <p className="text-xs text-zinc-500 text-center">
          {STEP_LABELS[step]}
        </p>
      </div>

      {/* Content card */}
      <div className="w-full max-w-xl bg-zinc-900/50 border border-zinc-800 rounded-xl p-8 min-h-[400px] flex flex-col">
        <div className="flex-1">
          {step === 0 && <WelcomeStep />}
          {step === 1 && <DependenciesStep />}
          {step === 2 && <BackendsStep settings={settings} onUpdate={updateSettings} />}
          {step === 3 && <ProjectDirStep settings={settings} onUpdate={updateSettings} />}
          {step === 4 && <NotificationsStep settings={settings} onUpdate={updateSettings} />}
          {step === 5 && <CompleteStep />}
        </div>

        {/* Navigation */}
        <div className="flex items-center justify-between mt-6 pt-4 border-t border-zinc-800">
          {step > 0 && step < 5 ? (
            <button
              onClick={prev}
              className="flex items-center gap-1.5 px-4 py-2 text-sm text-zinc-400 hover:text-zinc-200"
            >
              <ArrowLeft className="w-4 h-4" /> Back
            </button>
          ) : (
            <div />
          )}
          {step < 5 ? (
            <button
              onClick={next}
              className="flex items-center gap-1.5 px-4 py-2 text-sm bg-brand-600 text-white rounded-md hover:bg-brand-700"
            >
              {step === 0 ? "Get Started" : "Next"}{" "}
              <ArrowRight className="w-4 h-4" />
            </button>
          ) : (
            <button
              onClick={finish}
              className="flex items-center gap-1.5 px-6 py-2 text-sm bg-brand-600 text-white rounded-md hover:bg-brand-700"
            >
              <Zap className="w-4 h-4" /> Launch CreedFlow
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function WelcomeStep() {
  return (
    <div className="text-center space-y-4">
      <h2 className="text-2xl font-bold text-zinc-100">
        Welcome to CreedFlow
      </h2>
      <p className="text-sm text-zinc-400 max-w-sm mx-auto">
        AI-powered orchestration platform that autonomously manages your
        software projects. Let&apos;s set things up.
      </p>
      <div className="text-brand-400 text-4xl font-bold tracking-wider mt-6">
        CF
      </div>
    </div>
  );
}

function DependenciesStep() {
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
        System Dependencies
      </h3>
      <p className="text-xs text-zinc-500">
        CreedFlow needs these tools to orchestrate AI backends.
      </p>
      {loading ? (
        <div className="flex items-center gap-2 text-zinc-500 text-sm">
          <Loader2 className="w-4 h-4 animate-spin" /> Detecting...
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
                  Install
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
  const backends = [
    { key: "claudeEnabled" as const, label: "Claude", cloud: true },
    { key: "codexEnabled" as const, label: "Codex", cloud: true },
    { key: "geminiEnabled" as const, label: "Gemini", cloud: true },
    { key: "ollamaEnabled" as const, label: "Ollama", cloud: false },
    { key: "lmStudioEnabled" as const, label: "LM Studio", cloud: false },
    { key: "llamaCppEnabled" as const, label: "llama.cpp", cloud: false },
    { key: "mlxEnabled" as const, label: "MLX", cloud: false },
  ];

  const toggle = (key: keyof AppSettings) => {
    onUpdate({ ...settings, [key]: !settings[key] });
  };

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-zinc-200">AI Backends</h3>
      <p className="text-xs text-zinc-500">
        Enable the AI backends you want to use. Cloud backends are recommended.
      </p>
      <div className="space-y-1">
        {backends.map(({ key, label, cloud }) => (
          <div
            key={key}
            className="flex items-center justify-between py-2 px-3 rounded-md bg-zinc-800/30"
          >
            <div className="flex items-center gap-2">
              <span className="text-sm text-zinc-200">{label}</span>
              <span
                className={`text-[10px] px-1.5 py-0.5 rounded ${cloud ? "bg-blue-500/20 text-blue-400" : "bg-zinc-700 text-zinc-400"}`}
              >
                {cloud ? "Cloud" : "Local"}
              </span>
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
        ))}
      </div>
    </div>
  );
}

function ProjectDirStep({
  settings,
  onUpdate,
}: {
  settings: AppSettings;
  onUpdate: (s: AppSettings) => Promise<void>;
}) {
  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-zinc-200">Project Settings</h3>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">
          Projects Directory
        </label>
        <input
          type="text"
          value={settings.projectsDir}
          onChange={(e) => onUpdate({ ...settings, projectsDir: e.target.value })}
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
        />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-xs text-zinc-400 mb-1">
            Max Concurrency
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
        <div>
          <label className="block text-xs text-zinc-400 mb-1">
            Monthly Budget (USD)
          </label>
          <input
            type="number"
            value={settings.monthlyBudgetUsd}
            onChange={(e) =>
              onUpdate({
                ...settings,
                monthlyBudgetUsd: parseFloat(e.target.value) || 50,
              })
            }
            className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
          />
        </div>
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
  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-zinc-200">Notifications</h3>
      <p className="text-xs text-zinc-500">
        Optional: Configure Telegram notifications for task milestones.
      </p>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">
          Telegram Bot Token
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
          Telegram Chat ID
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
  return (
    <div className="text-center space-y-4">
      <div className="w-16 h-16 bg-green-500/20 rounded-full flex items-center justify-center mx-auto">
        <Check className="w-8 h-8 text-green-400" />
      </div>
      <h3 className="text-lg font-semibold text-zinc-200">All Set!</h3>
      <p className="text-sm text-zinc-400 max-w-sm mx-auto">
        CreedFlow is ready to orchestrate your projects. Create your first
        project to get started.
      </p>
    </div>
  );
}
