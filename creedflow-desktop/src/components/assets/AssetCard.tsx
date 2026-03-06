import {
  Image,
  Video,
  Music,
  Palette,
  FileText,
  CheckCircle,
  XCircle,
  Clock,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import type { GeneratedAsset } from "../../types/models";

const TYPE_CONFIG: Record<string, { icon: React.FC<{ className?: string }>; color: string }> = {
  image: { icon: Image, color: "text-emerald-400" },
  video: { icon: Video, color: "text-blue-400" },
  audio: { icon: Music, color: "text-purple-400" },
  design: { icon: Palette, color: "text-pink-400" },
  document: { icon: FileText, color: "text-amber-400" },
};

const STATUS_BADGE: Record<string, { icon: React.FC<{ className?: string }>; color: string; labelKey: string }> = {
  approved: { icon: CheckCircle, color: "text-green-400 bg-green-400/10", labelKey: "assets.status.approved" },
  rejected: { icon: XCircle, color: "text-red-400 bg-red-400/10", labelKey: "assets.status.rejected" },
  generated: { icon: Clock, color: "text-zinc-400 bg-zinc-400/10", labelKey: "assets.status.pending" },
};

function formatFileSize(bytes: number | null): string {
  if (!bytes) return "—";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

interface AssetCardProps {
  asset: GeneratedAsset;
  selected: boolean;
  onClick: () => void;
}

export function AssetCard({ asset, selected, onClick }: AssetCardProps) {
  const { t } = useTranslation();
  const typeConf = TYPE_CONFIG[asset.assetType] ?? TYPE_CONFIG.document;
  const TypeIcon = typeConf.icon;
  const status = STATUS_BADGE[asset.status] ?? STATUS_BADGE.generated;
  const StatusIcon = status.icon;

  return (
    <button
      onClick={onClick}
      className={`w-full text-left p-3 rounded-lg border transition-all ${
        selected
          ? "border-brand-500/50 bg-brand-600/10"
          : "border-zinc-800 bg-zinc-900/40 hover:bg-zinc-800/50 hover:border-zinc-700"
      }`}
    >
      {/* Thumbnail area */}
      <div className="aspect-[4/3] rounded-md bg-zinc-800/60 flex items-center justify-center mb-3">
        <TypeIcon className={`w-8 h-8 ${typeConf.color} opacity-60`} />
      </div>

      {/* Name + type */}
      <div className="flex items-start gap-2 mb-1.5">
        <TypeIcon className={`w-3.5 h-3.5 mt-0.5 flex-shrink-0 ${typeConf.color}`} />
        <span className="text-sm font-medium text-zinc-200 truncate flex-1">
          {asset.name}
        </span>
      </div>

      {/* Meta row */}
      <div className="flex items-center gap-2 text-[10px] text-zinc-500">
        <span>{formatFileSize(asset.fileSize)}</span>
        <span>·</span>
        <span>v{asset.version}</span>
        <span className="flex-1" />
        <span className={`flex items-center gap-1 px-1.5 py-0.5 rounded-full ${status.color}`}>
          <StatusIcon className="w-2.5 h-2.5" />
          {t(status.labelKey)}
        </span>
      </div>
    </button>
  );
}
