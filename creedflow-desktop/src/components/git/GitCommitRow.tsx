import type { GitLogEntry } from "../../tauri";
import { useTranslation } from "react-i18next";

export interface LaneData {
  lane: number;
  totalLanes: number;
  connections: { from: number; to: number; type: "continue" | "merge" | "branch" }[];
  color: string;
}

const LANE_COLORS = [
  "#6366f1", // brand/indigo
  "#22c55e", // green
  "#3b82f6", // blue
  "#f59e0b", // amber
  "#ef4444", // red
  "#a855f7", // purple
  "#06b6d4", // cyan
  "#ec4899", // pink
];

interface GitCommitRowProps {
  commit: GitLogEntry;
  laneData?: LaneData;
  onClick?: () => void;
  isSelected?: boolean;
}

export function GitCommitRow({ commit, laneData, onClick, isSelected }: GitCommitRowProps) {
  const { t } = useTranslation();
  const date = new Date(commit.timestamp * 1000);
  const timeAgo = formatRelativeTime(date, t);

  const branches = commit.decorations
    ? commit.decorations
        .replace(/[()]/g, "")
        .split(",")
        .map((d) => d.trim())
        .filter(Boolean)
    : [];

  return (
    <tr
      className={`border-b border-zinc-800/50 transition-colors cursor-pointer ${
        isSelected
          ? "bg-brand-600/10 hover:bg-brand-600/15"
          : "hover:bg-zinc-800/30"
      }`}
      onClick={onClick}
    >
      {/* Graph lane */}
      <td className="px-0 py-0 w-[60px]">
        {laneData && <LaneSvg data={laneData} />}
      </td>
      <td className="px-4 py-2">
        <span className="font-mono text-brand-400">{commit.shortHash}</span>
      </td>
      <td className="px-4 py-2 text-zinc-300 truncate max-w-[400px]">
        {commit.message}
      </td>
      <td className="px-4 py-2">
        <div className="flex gap-1 flex-wrap">
          {branches.map((branch) => (
            <BranchTag key={branch} name={branch} />
          ))}
        </div>
      </td>
      <td className="px-4 py-2 text-zinc-500 truncate">{commit.author}</td>
      <td className="px-4 py-2 text-zinc-500" title={date.toLocaleString()}>
        {timeAgo}
      </td>
    </tr>
  );
}

function LaneSvg({ data }: { data: LaneData }) {
  const width = 60;
  const height = 28;
  const laneWidth = 12;
  const cx = data.lane * laneWidth + laneWidth / 2 + 4;
  const cy = height / 2;

  return (
    <svg width={width} height={height} className="block">
      {/* Vertical continuation lines for active lanes */}
      {data.connections.map((conn, i) => {
        if (conn.type === "continue") {
          const x = conn.from * laneWidth + laneWidth / 2 + 4;
          return (
            <line
              key={`c-${i}`}
              x1={x}
              y1={0}
              x2={x}
              y2={height}
              stroke={LANE_COLORS[conn.from % LANE_COLORS.length]}
              strokeWidth={2}
              strokeOpacity={0.4}
            />
          );
        }
        if (conn.type === "merge") {
          const fromX = conn.from * laneWidth + laneWidth / 2 + 4;
          const toX = conn.to * laneWidth + laneWidth / 2 + 4;
          return (
            <line
              key={`m-${i}`}
              x1={fromX}
              y1={0}
              x2={toX}
              y2={cy}
              stroke={LANE_COLORS[conn.from % LANE_COLORS.length]}
              strokeWidth={2}
              strokeOpacity={0.5}
            />
          );
        }
        if (conn.type === "branch") {
          const fromX = conn.from * laneWidth + laneWidth / 2 + 4;
          const toX = conn.to * laneWidth + laneWidth / 2 + 4;
          return (
            <line
              key={`b-${i}`}
              x1={fromX}
              y1={cy}
              x2={toX}
              y2={height}
              stroke={LANE_COLORS[conn.to % LANE_COLORS.length]}
              strokeWidth={2}
              strokeOpacity={0.5}
            />
          );
        }
        return null;
      })}

      {/* Commit circle */}
      <circle
        cx={cx}
        cy={cy}
        r={4}
        fill={data.color}
        stroke={data.color}
        strokeWidth={1.5}
      />
    </svg>
  );
}

function BranchTag({ name }: { name: string }) {
  const isHead = name.includes("HEAD");
  const isTag = name.startsWith("tag:");
  const isOrigin = name.startsWith("origin/");

  let bgClass = "bg-zinc-800 text-zinc-400";
  if (isHead) bgClass = "bg-brand-600/20 text-brand-400";
  else if (isTag) bgClass = "bg-amber-900/30 text-amber-400";
  else if (isOrigin) bgClass = "bg-blue-900/30 text-blue-400";
  else bgClass = "bg-green-900/30 text-green-400";

  return (
    <span className={`text-[10px] px-1.5 py-0.5 rounded ${bgClass}`}>
      {name}
    </span>
  );
}

function formatRelativeTime(date: Date, t: (key: string, opts?: Record<string, unknown>) => string): string {
  const now = Date.now();
  const diff = now - date.getTime();
  const mins = Math.floor(diff / 60000);
  const hours = Math.floor(diff / 3600000);
  const days = Math.floor(diff / 86400000);

  if (mins < 1) return t("common.time.justNow");
  if (mins < 60) return t("common.time.minutesAgo", { count: mins });
  if (hours < 24) return t("common.time.hoursAgo", { count: hours });
  if (days < 30) return t("common.time.daysAgo", { count: days });
  return date.toLocaleDateString();
}
