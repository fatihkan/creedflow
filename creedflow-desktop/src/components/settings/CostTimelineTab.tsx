import { useMemo } from "react";
import type { CostBreakdown } from "../../tauri";
import { useTranslation } from "react-i18next";

interface CostTimelineTabProps {
  timeline: CostBreakdown[];
}

export function CostTimelineTab({ timeline }: CostTimelineTabProps) {
  const { t } = useTranslation();

  const maxCost = useMemo(
    () => Math.max(...timeline.map((d) => d.cost), 0.01),
    [timeline],
  );

  const reversedTimeline = useMemo(() => [...timeline].reverse(), [timeline]);

  return (
    <div className="space-y-3">
      <h3 className="text-xs font-medium text-zinc-400">{t("costs.last30Days")}</h3>
      {timeline.length === 0 ? (
        <p className="text-xs text-zinc-500">{t("costs.noCostData")}</p>
      ) : (
        <div className="space-y-1">
          <div className="flex items-end gap-1 h-32">
            {timeline.map((day) => {
              const height = (day.cost / maxCost) * 100;
              return (
                <div
                  key={day.label}
                  className="flex-1 group relative"
                  title={`${day.label}: $${day.cost.toFixed(2)}`}
                >
                  <div
                    className="bg-brand-500/60 hover:bg-brand-400/70 rounded-t transition-colors w-full"
                    style={{ height: `${Math.max(height, 2)}%` }}
                  />
                </div>
              );
            })}
          </div>
          <div className="mt-4 space-y-1">
            <div className="grid grid-cols-[1fr_80px_60px_80px] gap-2 px-3 py-1 text-[10px] text-zinc-500 uppercase tracking-wider">
              <span>{t("costs.headers.date")}</span>
              <span className="text-right">{t("costs.headers.cost")}</span>
              <span className="text-right">{t("costs.headers.tasks")}</span>
              <span className="text-right">{t("costs.headers.tokens")}</span>
            </div>
            {reversedTimeline.map((day) => (
              <div
                key={day.label}
                className="grid grid-cols-[1fr_80px_60px_80px] gap-2 items-center px-3 py-2 bg-zinc-900/30 rounded border border-zinc-800/50"
              >
                <span className="text-xs text-zinc-300">{day.label}</span>
                <span className="text-xs text-zinc-400 text-right">${day.cost.toFixed(4)}</span>
                <span className="text-xs text-zinc-500 text-right">{day.tasks}</span>
                <span className="text-xs text-zinc-500 text-right">{day.tokens.toLocaleString()}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
