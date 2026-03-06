import { useEffect, useState } from "react";
import {
  ArrowRight,
  ArrowLeft,
  Check,
  Zap,
} from "lucide-react";
import { useSettingsStore } from "../../store/settingsStore";
import { useTranslation } from "react-i18next";
import { WelcomeStep } from "./WelcomeStep";
import { EnvironmentStep } from "./EnvironmentStep";
import { DependenciesStep } from "./DependenciesStep";
import { BackendsStep } from "./BackendsStep";
import { ProjectSettingsStep } from "./ProjectSettingsStep";
import { NotificationsStep } from "./NotificationsStep";
import { CompleteStep } from "./CompleteStep";

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
