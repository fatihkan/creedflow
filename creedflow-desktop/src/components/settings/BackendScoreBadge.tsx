import type { BackendScore } from "../../types/models";

interface BackendScoreBadgeProps {
  score: BackendScore | undefined;
}

export function BackendScoreBadge({ score }: BackendScoreBadgeProps) {
  if (!score || score.sampleSize < 5) return null;

  const pct = Math.round(score.compositeScore * 100);
  const color =
    pct >= 70
      ? "bg-green-500/15 text-green-400"
      : pct >= 40
        ? "bg-yellow-500/15 text-yellow-400"
        : "bg-red-500/15 text-red-400";

  return (
    <span
      className={`text-[10px] font-bold font-mono px-1.5 py-0.5 rounded-full ${color}`}
      title={`Score: ${pct}/100 (${score.sampleSize} tasks)`}
    >
      {pct}
    </span>
  );
}
