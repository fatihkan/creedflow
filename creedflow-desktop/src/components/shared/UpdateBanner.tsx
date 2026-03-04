import { X, ExternalLink } from "lucide-react";
import type { UpdateInfo } from "../../tauri";

interface UpdateBannerProps {
  update: UpdateInfo;
  onDismiss: () => void;
  onViewRelease: () => void;
}

export function UpdateBanner({ update, onDismiss, onViewRelease }: UpdateBannerProps) {
  return (
    <div className="flex items-center justify-between px-4 py-2 bg-amber-900/30 border-b border-amber-800/50 text-amber-200">
      <div className="flex items-center gap-2 text-xs">
        <span>
          CreedFlow <strong>v{update.latestVersion}</strong> is available.
          You&apos;re on v{update.currentVersion}.
        </span>
        <button
          onClick={onViewRelease}
          className="flex items-center gap-1 text-amber-400 hover:text-amber-300 underline"
        >
          View Release
          <ExternalLink className="w-3 h-3" />
        </button>
      </div>
      <button
        onClick={onDismiss}
        className="p-0.5 rounded hover:bg-amber-800/40 text-amber-400 hover:text-amber-200"
      >
        <X className="w-3.5 h-3.5" />
      </button>
    </div>
  );
}
