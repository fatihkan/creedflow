import { useMemo } from "react";
import type { CostBreakdown } from "../../tauri";
import { useTranslation } from "react-i18next";

interface BreakdownTableProps {
  title: string;
  data: CostBreakdown[];
}

export function BreakdownTable({ title, data }: BreakdownTableProps) {
  const { t } = useTranslation();
  const maxCost = useMemo(
    () => Math.max(...data.map((d) => d.cost), 0.01),
    [data],
  );

  return (
    <div>
      <h3 className="text-xs font-medium text-zinc-400 mb-2">{title}</h3>
      {data.length === 0 ? (
        <p className="text-xs text-zinc-500">{t("costs.taskStats.noData")}</p>
      ) : (
        <div className="space-y-1">
          <div className="grid grid-cols-[1fr_80px_60px_80px] gap-2 px-3 py-1 text-[10px] text-zinc-500 uppercase tracking-wider">
            <span>{t("costs.headers.name")}</span>
            <span className="text-right">{t("costs.headers.cost")}</span>
            <span className="text-right">{t("costs.headers.tasks")}</span>
            <span className="text-right">{t("costs.headers.tokens")}</span>
          </div>
          {data.map((row) => (
            <div
              key={row.label}
              className="grid grid-cols-[1fr_80px_60px_80px] gap-2 items-center px-3 py-2 bg-zinc-900/30 rounded border border-zinc-800/50"
            >
              <div className="flex items-center gap-2">
                <div className="w-16 h-1.5 bg-zinc-800 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-brand-500/60 rounded-full"
                    style={{ width: `${(row.cost / maxCost) * 100}%` }}
                  />
                </div>
                <span className="text-xs text-zinc-300 capitalize">{row.label}</span>
              </div>
              <span className="text-xs text-zinc-400 text-right">${row.cost.toFixed(4)}</span>
              <span className="text-xs text-zinc-500 text-right">{row.tasks}</span>
              <span className="text-xs text-zinc-500 text-right">{row.tokens.toLocaleString()}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
