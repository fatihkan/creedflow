import { useEffect, useState } from "react";
import { X, XCircle, RotateCcw, Copy, Terminal } from "lucide-react";
import type { DeploymentInfo } from "../../types/models";
import * as api from "../../tauri";
import { useTranslation } from "react-i18next";
import { showErrorToast } from "../../hooks/useErrorToast";

const STATUS_COLORS: Record<string, string> = {
  pending: "text-zinc-400 bg-zinc-400/10",
  in_progress: "text-blue-400 bg-blue-400/10",
  success: "text-green-400 bg-green-400/10",
  failed: "text-red-400 bg-red-400/10",
  cancelled: "text-yellow-400 bg-yellow-400/10",
  rolled_back: "text-amber-400 bg-amber-400/10",
};

interface DeployDetailPanelProps {
  deployment: DeploymentInfo;
  onClose: () => void;
  onRefresh: () => void;
}

export function DeployDetailPanel({ deployment, onClose, onRefresh }: DeployDetailPanelProps) {
  const { t } = useTranslation();
  const [logs, setLogs] = useState<string | null>(null);
  const [loadingLogs, setLoadingLogs] = useState(false);

  useEffect(() => {
    setLoadingLogs(true);
    api
      .getDeploymentLogs(deployment.id)
      .then(setLogs)
      .catch((e) => showErrorToast("Failed to load deployment logs", e))
      .finally(() => setLoadingLogs(false));
  }, [deployment.id]);

  const canCancel = deployment.status === "pending" || deployment.status === "in_progress";
  const canRerun = deployment.status === "failed" || deployment.status === "cancelled";

  const handleCancel = async () => {
    await api.cancelDeployment(deployment.id);
    onRefresh();
  };

  const handleRerun = async () => {
    await api.createDeployment(
      deployment.projectId,
      deployment.environment,
      deployment.version,
      deployment.deployMethod ?? "docker",
    );
    onRefresh();
  };

  const statusColor = STATUS_COLORS[deployment.status] ?? STATUS_COLORS.pending;

  return (
    <div className="w-[360px] border-l border-zinc-800 bg-zinc-900/50 flex flex-col overflow-hidden">
      {/* Header */}
      <div className="flex items-center gap-2 px-4 py-3 border-b border-zinc-800">
        <h3 className="text-sm font-semibold text-zinc-200 flex-1 truncate">
          Deploy #{deployment.id.slice(0, 8)}
        </h3>
        <button
          onClick={onClose}
          className="p-1 rounded hover:bg-zinc-800 text-zinc-500 hover:text-zinc-300 transition-colors"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-4 py-3 space-y-4">
        {/* Status badge */}
        <div className="flex items-center gap-2">
          <span className={`text-xs font-medium px-2 py-1 rounded-full capitalize ${statusColor}`}>
            {deployment.status.replace("_", " ")}
          </span>
          <span className="text-[10px] text-zinc-500">{deployment.environment}</span>
        </div>

        {/* Metadata */}
        <div className="grid grid-cols-2 gap-3">
          <MetaField label={t("deployDetail.version")} value={deployment.version} />
          <MetaField label={t("deployDetail.method")} value={deployment.deployMethod ?? "—"} />
          <MetaField label={t("deployDetail.port")} value={deployment.port?.toString() ?? "—"} />
          <MetaField label={t("deployDetail.deployedBy")} value={deployment.deployedBy} />
          <MetaField label={t("deployDetail.created")} value={new Date(deployment.createdAt).toLocaleString()} />
          <MetaField
            label={t("deployDetail.completed")}
            value={deployment.completedAt ? new Date(deployment.completedAt).toLocaleString() : "—"}
          />
          {deployment.commitHash && (
            <MetaField label={t("deployDetail.commit")} value={deployment.commitHash.slice(0, 8)} />
          )}
          {deployment.containerId && (
            <MetaField label={t("deployDetail.container")} value={deployment.containerId.slice(0, 12)} />
          )}
        </div>

        {/* Actions */}
        <div className="flex items-center gap-2">
          {canCancel && (
            <button
              onClick={handleCancel}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-red-600/20 text-red-400 hover:bg-red-600/30 text-xs font-medium transition-colors"
            >
              <XCircle className="w-3.5 h-3.5" />
              {t("deployDetail.cancel")}
            </button>
          )}
          {canRerun && (
            <button
              onClick={handleRerun}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-blue-600/20 text-blue-400 hover:bg-blue-600/30 text-xs font-medium transition-colors"
            >
              <RotateCcw className="w-3.5 h-3.5" />
              {t("deployDetail.rerun")}
            </button>
          )}
        </div>

        {/* Logs */}
        <div>
          <div className="flex items-center gap-2 mb-2">
            <Terminal className="w-3.5 h-3.5 text-zinc-500" />
            <span className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              {t("deployDetail.logs")}
            </span>
            {logs && (
              <button
                onClick={() => navigator.clipboard.writeText(logs)}
                className="ml-auto p-1 rounded hover:bg-zinc-800 text-zinc-500 hover:text-zinc-300 transition-colors"
                title={t("deployDetail.copyLogs")}
              >
                <Copy className="w-3 h-3" />
              </button>
            )}
          </div>
          <div className="bg-zinc-950 border border-zinc-800 rounded-md p-3 max-h-[300px] overflow-y-auto">
            {loadingLogs ? (
              <p className="text-xs text-zinc-500">{t("deployDetail.loadingLogs")}</p>
            ) : logs ? (
              <pre className="text-[11px] text-zinc-400 font-mono whitespace-pre-wrap break-all leading-relaxed">
                {logs}
              </pre>
            ) : (
              <p className="text-xs text-zinc-500">{t("deployDetail.noLogs")}</p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function MetaField({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <span className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
        {label}
      </span>
      <p className="text-xs text-zinc-300 mt-0.5">{value}</p>
    </div>
  );
}
