import { useEffect, useState } from "react";
import { Download, Loader2 } from "lucide-react";
import * as api from "../../tauri";
import type { DependencyStatus } from "../../types/models";
import { useTranslation } from "react-i18next";
import { showErrorToast } from "../../hooks/useErrorToast";

export function DependenciesStep() {
  const { t } = useTranslation();
  const [deps, setDeps] = useState<DependencyStatus[]>([]);
  const [installing, setInstalling] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api
      .detectDependencies()
      .then(setDeps)
      .catch((e) => showErrorToast("Failed to detect dependencies", e))
      .finally(() => setLoading(false));
  }, []);

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
