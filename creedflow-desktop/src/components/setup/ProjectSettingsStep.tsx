import type { AppSettings } from "../../types/models";
import { useTranslation } from "react-i18next";

interface ProjectSettingsStepProps {
  settings: AppSettings;
  onUpdate: (s: AppSettings) => Promise<void>;
}

export function ProjectSettingsStep({ settings, onUpdate }: ProjectSettingsStepProps) {
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
