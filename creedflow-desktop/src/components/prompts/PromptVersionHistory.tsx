import { useEffect, useState } from "react";
import { X, GitCompare, Clock } from "lucide-react";
import { useTranslation } from "react-i18next";
import type { PromptVersion, PromptVersionDiff } from "../../types/models";
import * as api from "../../tauri";
import { PromptDiffViewer } from "./PromptDiffViewer";
import { useErrorToast } from "../../hooks/useErrorToast";
import { FocusTrap } from "../shared/FocusTrap";

interface Props {
  promptId: string;
  promptTitle: string;
  onClose: () => void;
}

export function PromptVersionHistory({ promptId, promptTitle, onClose }: Props) {
  const { t } = useTranslation();
  const [versions, setVersions] = useState<PromptVersion[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [diff, setDiff] = useState<PromptVersionDiff | null>(null);
  const [comparing, setComparing] = useState(false);
  const withError = useErrorToast();

  useEffect(() => {
    (async () => {
      setLoading(true);
      await withError(async () => {
        const data = await api.getPromptVersions(promptId);
        setVersions(data);
      });
      setLoading(false);
    })();
  }, [promptId]);

  const toggleVersion = (version: number) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(version)) {
        next.delete(version);
      } else {
        if (next.size >= 2) {
          const arr = Array.from(next);
          next.delete(arr[0]);
        }
        next.add(version);
      }
      return next;
    });
    setDiff(null);
  };

  const handleCompare = async () => {
    const [a, b] = Array.from(selected).sort((x, y) => x - y);
    if (a == null || b == null) return;
    setComparing(true);
    await withError(async () => {
      const result = await api.getPromptVersionDiff(promptId, a, b);
      setDiff(result);
    });
    setComparing(false);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" role="dialog" aria-modal="true" aria-labelledby="version-history-title">
      <FocusTrap>
      <div className="bg-zinc-900 border border-zinc-700 rounded-xl w-[640px] max-h-[80vh] flex flex-col shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-3 border-b border-zinc-800">
          <div className="flex items-center gap-2">
            <Clock className="w-4 h-4 text-zinc-400" />
            <h3 id="version-history-title" className="text-sm font-semibold text-zinc-200">
              {t("prompts.versionHistory.title")}
            </h3>
            <span className="text-xs text-zinc-500 truncate max-w-[200px]">
              {promptTitle}
            </span>
          </div>
          <button onClick={onClose} className="text-zinc-500 hover:text-zinc-300" aria-label="Close version history">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-5 space-y-4">
          {loading ? (
            <div className="text-sm text-zinc-500 text-center py-8">
              {t("prompts.versionHistory.loading")}
            </div>
          ) : versions.length === 0 ? (
            <div className="text-sm text-zinc-500 text-center py-8">
              {t("prompts.versionHistory.empty")}
            </div>
          ) : (
            <>
              {/* Version list */}
              <div className="space-y-1.5">
                {versions.map((v) => (
                  <label
                    key={v.id}
                    className={`flex items-center gap-3 px-3 py-2 rounded-md cursor-pointer transition-colors ${
                      selected.has(v.version)
                        ? "bg-brand-600/15 border border-brand-500/30"
                        : "bg-zinc-800/40 border border-transparent hover:bg-zinc-800/60"
                    }`}
                  >
                    <input
                      type="checkbox"
                      checked={selected.has(v.version)}
                      onChange={() => toggleVersion(v.version)}
                      className="accent-brand-500"
                    />
                    <span className="text-xs font-medium text-zinc-200 w-8">
                      v{v.version}
                    </span>
                    <span className="text-xs text-zinc-300 flex-1 truncate">
                      {v.title}
                    </span>
                    {v.changeNote && (
                      <span className="text-[10px] text-zinc-500 truncate max-w-[150px]">
                        {v.changeNote}
                      </span>
                    )}
                    <span className="text-[10px] text-zinc-600">
                      {new Date(v.createdAt).toLocaleDateString()}
                    </span>
                  </label>
                ))}
              </div>

              {/* Compare button */}
              <div className="flex justify-center">
                <button
                  onClick={handleCompare}
                  disabled={selected.size !== 2 || comparing}
                  className="flex items-center gap-1.5 px-4 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded disabled:opacity-40 transition-colors"
                >
                  <GitCompare className="w-3.5 h-3.5" />
                  {comparing ? t("prompts.versionHistory.comparing") : t("prompts.versionHistory.compare")}
                </button>
              </div>

              {/* Diff viewer */}
              {diff && <PromptDiffViewer diff={diff} />}
            </>
          )}
        </div>
      </div>
      </FocusTrap>
    </div>
  );
}
