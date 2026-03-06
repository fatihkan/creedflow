import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useCostStore } from "../../store/costStore";
import type { CostBudget, BudgetUtilization } from "../../types/models";
import { showErrorToast } from "../../hooks/useErrorToast";

const newBudget = (): CostBudget => ({
  id: crypto.randomUUID(),
  scope: "global",
  projectId: null,
  period: "monthly",
  limitUsd: 50,
  warnThreshold: 0.8,
  criticalThreshold: 0.95,
  pauseOnExceed: false,
  isEnabled: true,
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString(),
});

export function CostBudgetTab() {
  const { t } = useTranslation();
  const {
    budgets,
    utilizations,
    fetchBudgets,
    fetchUtilizations,
    upsertBudget,
    deleteBudget,
    acknowledgeAlert,
  } = useCostStore();

  const [showForm, setShowForm] = useState(false);
  const [editBudget, setEditBudget] = useState<CostBudget | null>(null);

  useEffect(() => {
    fetchBudgets();
    fetchUtilizations();
  }, [fetchBudgets, fetchUtilizations]);

  const handleSave = async (budget: CostBudget) => {
    try {
      await upsertBudget(budget);
      setShowForm(false);
      setEditBudget(null);
    } catch (e) {
      showErrorToast(t("costs.budget.saveFailed"), e);
    }
  };

  const handleDelete = async (id: string) => {
    try {
      await deleteBudget(id);
    } catch (e) {
      showErrorToast(t("costs.budget.deleteFailed"), e);
    }
  };

  // Build utilization map
  const utilMap = new Map<string, BudgetUtilization>();
  for (const u of utilizations) {
    utilMap.set(u.budget.id, u);
  }

  return (
    <div className="p-4 space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">
          {t("costs.budget.title")}
        </h3>
        <button
          onClick={() => {
            setEditBudget(null);
            setShowForm(true);
          }}
          className="text-xs text-brand-400 hover:text-brand-300 flex items-center gap-1"
        >
          <span>+</span> {t("costs.budget.add")}
        </button>
      </div>

      {/* Budget cards */}
      {budgets.length === 0 && !showForm ? (
        <div className="flex flex-col items-center justify-center py-16 text-zinc-500">
          <svg className="w-10 h-10 mb-3 text-zinc-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5z" />
          </svg>
          <p className="text-sm">{t("costs.budget.noBudgets")}</p>
          <p className="text-xs text-zinc-600 mt-1">{t("costs.budget.noBudgetsHint")}</p>
        </div>
      ) : (
        budgets.map((budget) => {
          const util = utilMap.get(budget.id);
          const spend = util?.currentSpend ?? 0;
          const pct = budget.limitUsd > 0 ? spend / budget.limitUsd : 0;
          const barColor =
            pct >= 1.0
              ? "bg-red-500"
              : pct >= budget.criticalThreshold
                ? "bg-orange-500"
                : pct >= budget.warnThreshold
                  ? "bg-yellow-500"
                  : "bg-green-500";

          return (
            <div
              key={budget.id}
              className="p-4 bg-zinc-900/50 rounded-lg border border-zinc-800"
            >
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-zinc-200">
                    {budget.scope === "global" ? "Global" : "Project"}
                  </span>
                  <span className="text-[10px] text-zinc-500">
                    {budget.period}
                  </span>
                </div>
                <span className="text-lg font-bold font-mono text-zinc-200">
                  {Math.round(pct * 100)}%
                </span>
              </div>

              <div className="text-sm text-zinc-300 mb-2">
                ${spend.toFixed(2)} / ${budget.limitUsd.toFixed(2)}
              </div>

              {/* Utilization bar */}
              <div className="h-2 bg-zinc-800 rounded-full overflow-hidden mb-3">
                <div
                  className={`h-full rounded-full ${barColor} opacity-70`}
                  style={{ width: `${Math.min(pct * 100, 100)}%` }}
                />
              </div>

              <div className="flex items-center justify-between text-[10px] text-zinc-500">
                <div className="flex items-center gap-3">
                  {budget.pauseOnExceed && (
                    <span className="text-orange-400">Auto-pause</span>
                  )}
                  <span>Warn: {Math.round(budget.warnThreshold * 100)}%</span>
                  <span>Critical: {Math.round(budget.criticalThreshold * 100)}%</span>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => {
                      setEditBudget(budget);
                      setShowForm(true);
                    }}
                    className="text-brand-400 hover:text-brand-300"
                  >
                    {t("costs.budget.edit")}
                  </button>
                  <button
                    onClick={() => handleDelete(budget.id)}
                    className="text-red-400 hover:text-red-300"
                  >
                    {t("costs.budget.delete")}
                  </button>
                </div>
              </div>

              {/* Alerts for this budget */}
              {util && util.alerts.length > 0 && (
                <div className="mt-3 pt-3 border-t border-zinc-800 space-y-1">
                  {util.alerts.slice(0, 3).map((alert) => (
                    <div
                      key={alert.id}
                      className="flex items-center justify-between text-[11px]"
                    >
                      <div className="flex items-center gap-1.5">
                        <span
                          className={
                            alert.thresholdType === "warn"
                              ? "text-yellow-400"
                              : "text-red-400"
                          }
                        >
                          {alert.thresholdType}
                        </span>
                        <span className="text-zinc-500">
                          {Math.round(alert.percentage * 100)}%
                        </span>
                      </div>
                      {!alert.acknowledgedAt && (
                        <button
                          onClick={() => acknowledgeAlert(alert.id)}
                          className="text-zinc-500 hover:text-zinc-300"
                        >
                          {t("costs.budget.acknowledge")}
                        </button>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        })
      )}

      {/* Budget form modal */}
      {showForm && (
        <BudgetForm
          budget={editBudget ?? newBudget()}
          onSave={handleSave}
          onCancel={() => {
            setShowForm(false);
            setEditBudget(null);
          }}
        />
      )}
    </div>
  );
}

// ─── Budget Form ─────────────────────────────────────────────────────────────

function BudgetForm({
  budget,
  onSave,
  onCancel,
}: {
  budget: CostBudget;
  onSave: (b: CostBudget) => void;
  onCancel: () => void;
}) {
  const { t } = useTranslation();
  const [form, setForm] = useState<CostBudget>(budget);

  return (
    <div className="p-4 bg-zinc-900 rounded-lg border border-zinc-700 space-y-3">
      <h4 className="text-sm font-medium text-zinc-200">
        {budget.createdAt === budget.updatedAt
          ? t("costs.budget.newBudget")
          : t("costs.budget.editBudget")}
      </h4>

      <div className="grid grid-cols-2 gap-3">
        <label className="text-[11px] text-zinc-400">
          {t("costs.budget.scope")}
          <select
            value={form.scope}
            onChange={(e) =>
              setForm({ ...form, scope: e.target.value as "global" | "project" })
            }
            className="mt-1 w-full bg-zinc-800 border border-zinc-700 rounded px-2 py-1 text-xs text-zinc-200"
          >
            <option value="global">Global</option>
            <option value="project">Project</option>
          </select>
        </label>

        <label className="text-[11px] text-zinc-400">
          {t("costs.budget.period")}
          <select
            value={form.period}
            onChange={(e) =>
              setForm({
                ...form,
                period: e.target.value as "daily" | "weekly" | "monthly",
              })
            }
            className="mt-1 w-full bg-zinc-800 border border-zinc-700 rounded px-2 py-1 text-xs text-zinc-200"
          >
            <option value="daily">Daily</option>
            <option value="weekly">Weekly</option>
            <option value="monthly">Monthly</option>
          </select>
        </label>

        <label className="text-[11px] text-zinc-400">
          {t("costs.budget.limit")} ($)
          <input
            type="number"
            value={form.limitUsd}
            onChange={(e) =>
              setForm({ ...form, limitUsd: parseFloat(e.target.value) || 0 })
            }
            className="mt-1 w-full bg-zinc-800 border border-zinc-700 rounded px-2 py-1 text-xs text-zinc-200"
          />
        </label>

        <label className="text-[11px] text-zinc-400">
          {t("costs.budget.warnAt")} (%)
          <input
            type="number"
            value={Math.round(form.warnThreshold * 100)}
            onChange={(e) =>
              setForm({
                ...form,
                warnThreshold: (parseInt(e.target.value) || 0) / 100,
              })
            }
            className="mt-1 w-full bg-zinc-800 border border-zinc-700 rounded px-2 py-1 text-xs text-zinc-200"
          />
        </label>

        <label className="text-[11px] text-zinc-400">
          {t("costs.budget.criticalAt")} (%)
          <input
            type="number"
            value={Math.round(form.criticalThreshold * 100)}
            onChange={(e) =>
              setForm({
                ...form,
                criticalThreshold: (parseInt(e.target.value) || 0) / 100,
              })
            }
            className="mt-1 w-full bg-zinc-800 border border-zinc-700 rounded px-2 py-1 text-xs text-zinc-200"
          />
        </label>

        <label className="flex items-center gap-2 text-[11px] text-zinc-400 pt-4">
          <input
            type="checkbox"
            checked={form.pauseOnExceed}
            onChange={(e) =>
              setForm({ ...form, pauseOnExceed: e.target.checked })
            }
            className="rounded bg-zinc-800 border-zinc-700"
          />
          {t("costs.budget.pauseOnExceed")}
        </label>
      </div>

      <div className="flex justify-end gap-2 pt-2">
        <button
          onClick={onCancel}
          className="text-xs text-zinc-400 hover:text-zinc-200 px-3 py-1.5"
        >
          {t("common.cancel")}
        </button>
        <button
          onClick={() => onSave({ ...form, updatedAt: new Date().toISOString() })}
          className="text-xs bg-brand-600 hover:bg-brand-500 text-white px-3 py-1.5 rounded"
        >
          {t("common.save")}
        </button>
      </div>
    </div>
  );
}
