import { useEffect } from "react";
import { useSettingsStore } from "../../store/settingsStore";

export function BackendSettings() {
  const { backends, fetchBackends, toggleBackend } = useSettingsStore();

  useEffect(() => {
    fetchBackends();
  }, [fetchBackends]);

  return (
    <section>
      <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
        AI Backends
      </h3>
      <div className="space-y-2">
        {backends.map((backend) => (
          <div
            key={backend.backendType}
            className="flex items-center justify-between p-3 bg-zinc-900/50 rounded-lg border border-zinc-800"
          >
            <div className="flex items-center gap-3">
              <div
                className="w-2 h-2 rounded-full"
                style={{ backgroundColor: backend.color }}
              />
              <div>
                <div className="flex items-center gap-2">
                  <span className="text-sm text-zinc-200">
                    {backend.displayName}
                  </span>
                  {backend.isLocal && (
                    <span className="text-[10px] bg-zinc-800 text-zinc-500 px-1.5 py-0.5 rounded">
                      Local
                    </span>
                  )}
                </div>
                <span className="text-[10px] text-zinc-500">
                  {backend.isAvailable ? (
                    <span className="text-green-500">Available</span>
                  ) : (
                    <span className="text-zinc-600">Not found</span>
                  )}
                  {backend.cliPath && (
                    <span className="ml-2 text-zinc-600">
                      {backend.cliPath}
                    </span>
                  )}
                </span>
              </div>
            </div>

            <label className="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                checked={backend.isEnabled}
                onChange={(e) =>
                  toggleBackend(backend.backendType, e.target.checked)
                }
                className="sr-only peer"
              />
              <div className="w-9 h-5 bg-zinc-700 rounded-full peer peer-checked:bg-brand-600 after:content-[''] after:absolute after:top-0.5 after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-full" />
            </label>
          </div>
        ))}
      </div>
    </section>
  );
}
