import { useEffect } from "react";
import { useTranslation } from "react-i18next";
import { useCostStore } from "../../store/costStore";
import { BackendScoreBadge } from "./BackendScoreBadge";

const DIMENSION_COLORS: Record<string, string> = {
  costEfficiency: "bg-green-500",
  speed: "bg-blue-500",
  reliability: "bg-orange-500",
  quality: "bg-purple-500",
};

const DIMENSION_LABELS: Record<string, string> = {
  costEfficiency: "Cost Efficiency",
  speed: "Speed",
  reliability: "Reliability",
  quality: "Quality",
};

export function CostEfficiencyTab() {
  const { t } = useTranslation();
  const { scores, fetchScores } = useCostStore();

  useEffect(() => {
    fetchScores();
  }, [fetchScores]);

  if (scores.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-zinc-500">
        <svg className="w-10 h-10 mb-3 text-zinc-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
        </svg>
        <p className="text-sm">{t("costs.efficiency.noData")}</p>
        <p className="text-xs text-zinc-600 mt-1">{t("costs.efficiency.noDataHint")}</p>
      </div>
    );
  }

  const sorted = [...scores].sort((a, b) => b.compositeScore - a.compositeScore);

  return (
    <div className="space-y-4 p-4">
      {sorted.map((score) => (
        <div
          key={score.id}
          className="p-4 bg-zinc-900/50 rounded-lg border border-zinc-800"
        >
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <span className="text-sm font-medium text-zinc-200">
                {score.backendType.charAt(0).toUpperCase() + score.backendType.slice(1)}
              </span>
              <BackendScoreBadge score={score} />
            </div>
            <span className="text-[10px] text-zinc-500">
              {score.sampleSize} {t("costs.efficiency.tasks")}
            </span>
          </div>

          <div className="space-y-2">
            {(["costEfficiency", "speed", "reliability", "quality"] as const).map(
              (dim) => {
                const value = score[dim];
                const pct = Math.round(value * 100);
                return (
                  <div key={dim} className="flex items-center gap-2">
                    <span className="text-[11px] text-zinc-400 w-24 shrink-0">
                      {DIMENSION_LABELS[dim]}
                    </span>
                    <div className="flex-1 h-2 bg-zinc-800 rounded-full overflow-hidden">
                      <div
                        className={`h-full rounded-full ${DIMENSION_COLORS[dim]} opacity-60`}
                        style={{ width: `${Math.min(pct, 100)}%` }}
                      />
                    </div>
                    <span className="text-[11px] text-zinc-500 font-mono w-8 text-right">
                      {pct}
                    </span>
                  </div>
                );
              }
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
