import { useEffect, useState } from "react";
import {
  Download,
  Loader2,
  AlertTriangle,
} from "lucide-react";
import { save } from "@tauri-apps/plugin-dialog";
import * as api from "../../tauri";
import { showErrorToast } from "../../hooks/useErrorToast";

export function DatabaseSettings() {
  const [dbInfo, setDbInfo] = useState<api.DbInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [confirmReset, setConfirmReset] = useState(false);

  useEffect(() => {
    api.getDbInfo()
      .then(setDbInfo)
      .catch((e) => showErrorToast("Failed to load database info", e))
      .finally(() => setLoading(false));
  }, []);

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  const handleVacuum = async () => {
    setWorking(true);
    try {
      await api.vacuumDatabase();
      setResult("Vacuum completed");
      const info = await api.getDbInfo();
      setDbInfo(info);
    } catch (e) {
      setResult(`Error: ${e}`);
    } finally {
      setWorking(false);
    }
  };

  const handlePrune = async () => {
    setWorking(true);
    try {
      const count = await api.pruneOldLogs(30);
      setResult(`Pruned ${count} log entries`);
      const info = await api.getDbInfo();
      setDbInfo(info);
    } catch (e) {
      setResult(`Error: ${e}`);
    } finally {
      setWorking(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-zinc-500 text-xs">
        <Loader2 className="w-3.5 h-3.5 animate-spin" /> Loading database info...
      </div>
    );
  }

  return (
    <div className="space-y-5">
      {dbInfo && (
        <section>
          <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
            Database Info
          </h3>
          <div className="space-y-2 text-xs">
            <div className="flex justify-between py-1.5 px-3 rounded bg-zinc-800/30">
              <span className="text-zinc-400">File Size</span>
              <span className="text-zinc-200 font-mono">{formatSize(dbInfo.sizeBytes)}</span>
            </div>
            <div className="flex justify-between py-1.5 px-3 rounded bg-zinc-800/30">
              <span className="text-zinc-400">Path</span>
              <span className="text-zinc-500 font-mono text-[10px] truncate max-w-[300px]">{dbInfo.path}</span>
            </div>
            <details className="text-xs">
              <summary className="cursor-pointer text-zinc-400 hover:text-zinc-300 py-1">
                Tables ({dbInfo.tables.length})
              </summary>
              <div className="mt-1 space-y-0.5">
                {dbInfo.tables.map((t) => (
                  <div key={t.name} className="flex justify-between py-1 px-3 rounded bg-zinc-800/20">
                    <span className="text-zinc-400 font-mono">{t.name}</span>
                    <span className="text-zinc-500">{t.rowCount} rows</span>
                  </div>
                ))}
              </div>
            </details>
          </div>
        </section>
      )}

      <section>
        <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
          Maintenance
        </h3>
        <div className="flex flex-wrap gap-2">
          <button
            onClick={handleVacuum}
            disabled={working}
            className="px-4 py-1.5 text-xs bg-zinc-800 border border-zinc-700 text-zinc-300 rounded hover:bg-zinc-700 disabled:opacity-50"
          >
            {working ? "Working..." : "Vacuum"}
          </button>
          <button
            onClick={handlePrune}
            disabled={working}
            className="px-4 py-1.5 text-xs bg-zinc-800 border border-zinc-700 text-zinc-300 rounded hover:bg-zinc-700 disabled:opacity-50"
          >
            Prune Logs (&gt; 30 days)
          </button>
          <button
            onClick={async () => {
              try {
                const path = await save({
                  defaultPath: "creedflow-export.json",
                  filters: [{ name: "JSON", extensions: ["json"] }],
                });
                if (path) {
                  setWorking(true);
                  await api.exportDatabaseJson(path);
                  setResult("Database exported to JSON");
                  setWorking(false);
                }
              } catch (e) {
                setResult(`Export error: ${e}`);
                setWorking(false);
              }
            }}
            disabled={working}
            className="flex items-center gap-1.5 px-4 py-1.5 text-xs bg-zinc-800 border border-zinc-700 text-zinc-300 rounded hover:bg-zinc-700 disabled:opacity-50"
          >
            <Download className="w-3 h-3" />
            Export JSON
          </button>
        </div>
        {result && (
          <p className="text-[10px] text-zinc-500 mt-2">{result}</p>
        )}
      </section>

      <section>
        <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">
          Danger Zone
        </h3>
        {!confirmReset ? (
          <button
            onClick={() => setConfirmReset(true)}
            className="flex items-center gap-1.5 px-4 py-1.5 text-xs bg-red-900/30 border border-red-800/50 text-red-400 rounded hover:bg-red-900/50"
          >
            <AlertTriangle className="w-3 h-3" />
            Factory Reset
          </button>
        ) : (
          <div className="p-3 bg-red-950/50 border border-red-800/50 rounded-lg space-y-2">
            <p className="text-xs text-red-300 font-medium">
              This will permanently delete all projects, tasks, reviews, and data. This cannot be undone.
            </p>
            <div className="flex gap-2">
              <button
                onClick={async () => {
                  setWorking(true);
                  try {
                    await api.factoryResetDatabase();
                    setResult("Factory reset complete. All data cleared.");
                    const info = await api.getDbInfo();
                    setDbInfo(info);
                  } catch (e) {
                    setResult(`Reset error: ${e}`);
                  } finally {
                    setWorking(false);
                    setConfirmReset(false);
                  }
                }}
                disabled={working}
                className="px-4 py-1.5 text-xs bg-red-700 text-white rounded hover:bg-red-600 disabled:opacity-50"
              >
                {working ? "Resetting..." : "Confirm Reset"}
              </button>
              <button
                onClick={() => setConfirmReset(false)}
                className="px-4 py-1.5 text-xs bg-zinc-800 border border-zinc-700 text-zinc-300 rounded hover:bg-zinc-700"
              >
                Cancel
              </button>
            </div>
          </div>
        )}
      </section>
    </div>
  );
}
