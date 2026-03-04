import { useEffect, useState } from "react";
import {
  X,
  CheckCircle,
  XCircle,
  Trash2,
  Copy,
  Image,
  Video,
  Music,
  Palette,
  FileText,
  History,
} from "lucide-react";
import type { GeneratedAsset } from "../../types/models";
import * as api from "../../tauri";
import { useAssetStore } from "../../store/assetStore";
import { FocusTrap } from "../shared/FocusTrap";
import { useTranslation } from "react-i18next";

const TYPE_ICONS: Record<string, React.FC<{ className?: string }>> = {
  image: Image,
  video: Video,
  audio: Music,
  design: Palette,
  document: FileText,
};

interface AssetDetailSheetProps {
  asset: GeneratedAsset;
  onClose: () => void;
}

export function AssetDetailSheet({ asset, onClose }: AssetDetailSheetProps) {
  const { t } = useTranslation();
  const [versions, setVersions] = useState<GeneratedAsset[]>([]);
  const [showVersions, setShowVersions] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const approveAsset = useAssetStore((s) => s.approveAsset);
  const rejectAsset = useAssetStore((s) => s.rejectAsset);
  const deleteAsset = useAssetStore((s) => s.deleteAsset);

  useEffect(() => {
    api.getAssetVersions(asset.id).then(setVersions).catch(console.error);
  }, [asset.id]);

  const TypeIcon = TYPE_ICONS[asset.assetType] ?? FileText;

  const handleApprove = async () => {
    await approveAsset(asset.id);
  };

  const handleReject = async () => {
    await rejectAsset(asset.id);
  };

  const handleDelete = async () => {
    await deleteAsset(asset.id);
    onClose();
  };

  const copyPath = () => {
    navigator.clipboard.writeText(asset.filePath);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" role="dialog" aria-modal="true" aria-labelledby="asset-detail-title">
      <FocusTrap>
      <div className="bg-zinc-900 border border-zinc-700 rounded-xl w-[520px] max-h-[80vh] flex flex-col shadow-2xl">
        {/* Header */}
        <div className="flex items-center gap-3 px-5 py-4 border-b border-zinc-800">
          <TypeIcon className="w-5 h-5 text-brand-400" />
          <h2 className="text-sm font-semibold text-zinc-100 flex-1 truncate">
            {asset.name}
          </h2>
          <button
            onClick={onClose}
            className="p-1 rounded-md hover:bg-zinc-800 text-zinc-500 hover:text-zinc-300 transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4">
          {/* Preview area */}
          <div className="aspect-video rounded-lg bg-zinc-800/60 flex items-center justify-center">
            <TypeIcon className="w-12 h-12 text-zinc-600" />
          </div>

          {/* Description */}
          {asset.description && (
            <div>
              <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
                {t("assets.detail.description")}
              </label>
              <p className="text-sm text-zinc-300 mt-1">{asset.description}</p>
            </div>
          )}

          {/* Metadata grid */}
          <div className="grid grid-cols-2 gap-3">
            <MetaField label={t("assets.detail.type")} value={asset.assetType} />
            <MetaField label={t("assets.detail.status")} value={asset.status} />
            <MetaField label={t("assets.detail.version")} value={`v${asset.version}`} />
            <MetaField
              label={t("assets.detail.size")}
              value={
                asset.fileSize
                  ? asset.fileSize < 1024 * 1024
                    ? `${(asset.fileSize / 1024).toFixed(1)} KB`
                    : `${(asset.fileSize / (1024 * 1024)).toFixed(1)} MB`
                  : "—"
              }
            />
            <MetaField label={t("assets.detail.agent")} value={asset.agentType} />
            <MetaField label={t("assets.detail.mime")} value={asset.mimeType ?? "—"} />
            <MetaField label={t("assets.detail.created")} value={new Date(asset.createdAt).toLocaleString()} />
            <MetaField label={t("assets.detail.updated")} value={new Date(asset.updatedAt).toLocaleString()} />
          </div>

          {/* File path */}
          <div>
            <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
              {t("assets.detail.filePath")}
            </label>
            <div className="flex items-center gap-2 mt-1">
              <code className="text-xs text-zinc-400 bg-zinc-800/60 px-2 py-1 rounded flex-1 truncate">
                {asset.filePath}
              </code>
              <button
                onClick={copyPath}
                className="p-1.5 rounded-md hover:bg-zinc-800 text-zinc-500 hover:text-zinc-300 transition-colors"
                title={t("assets.detail.copyPath")}
              >
                <Copy className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          {/* Checksum */}
          {asset.checksum && (
            <div>
              <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
                SHA256
              </label>
              <code className="block text-[10px] text-zinc-500 bg-zinc-800/40 px-2 py-1 rounded mt-1 break-all">
                {asset.checksum}
              </code>
            </div>
          )}

          {/* Version history */}
          {versions.length > 1 && (
            <div>
              <button
                onClick={() => setShowVersions(!showVersions)}
                className="flex items-center gap-2 text-xs text-zinc-400 hover:text-zinc-200 transition-colors"
              >
                <History className="w-3.5 h-3.5" />
                <span>
                  {showVersions ? t("assets.detail.hideVersions", { count: versions.length }) : t("assets.detail.showVersions", { count: versions.length })}
                </span>
              </button>
              {showVersions && (
                <div className="mt-2 space-y-1.5">
                  {versions.map((v) => (
                    <div
                      key={v.id}
                      className={`flex items-center gap-3 px-3 py-2 rounded-md text-xs ${
                        v.id === asset.id
                          ? "bg-brand-600/10 border border-brand-500/30"
                          : "bg-zinc-800/40"
                      }`}
                    >
                      <span className="text-zinc-500 w-8">v{v.version}</span>
                      <span className="flex-1 text-zinc-300 truncate">{v.name}</span>
                      <span className="text-zinc-500">
                        {new Date(v.createdAt).toLocaleDateString()}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Actions */}
        <div className="flex items-center gap-2 px-5 py-3 border-t border-zinc-800">
          {asset.status === "generated" && (
            <>
              <button
                onClick={handleApprove}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-green-600/20 text-green-400 hover:bg-green-600/30 text-xs font-medium transition-colors"
              >
                <CheckCircle className="w-3.5 h-3.5" />
                {t("assets.detail.approve")}
              </button>
              <button
                onClick={handleReject}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-red-600/20 text-red-400 hover:bg-red-600/30 text-xs font-medium transition-colors"
              >
                <XCircle className="w-3.5 h-3.5" />
                {t("assets.detail.reject")}
              </button>
            </>
          )}
          <div className="flex-1" />
          {confirmDelete ? (
            <div className="flex items-center gap-2">
              <span className="text-xs text-zinc-500">{t("assets.detail.deleteConfirm")}</span>
              <button
                onClick={handleDelete}
                className="px-2 py-1 rounded text-xs bg-red-600 text-white hover:bg-red-500 transition-colors"
              >
                {t("assets.detail.confirm")}
              </button>
              <button
                onClick={() => setConfirmDelete(false)}
                className="px-2 py-1 rounded text-xs bg-zinc-700 text-zinc-300 hover:bg-zinc-600 transition-colors"
              >
                {t("assets.detail.cancel")}
              </button>
            </div>
          ) : (
            <button
              onClick={() => setConfirmDelete(true)}
              className="p-1.5 rounded-md hover:bg-zinc-800 text-zinc-500 hover:text-red-400 transition-colors"
              title="Delete asset"
            >
              <Trash2 className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>
      </FocusTrap>
    </div>
  );
}

function MetaField({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <span className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
        {label}
      </span>
      <p className="text-xs text-zinc-300 mt-0.5 capitalize">{value}</p>
    </div>
  );
}
