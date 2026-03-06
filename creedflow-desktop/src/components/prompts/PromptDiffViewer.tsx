import { useTranslation } from "react-i18next";
import type { PromptVersionDiff } from "../../types/models";

interface Props {
  diff: PromptVersionDiff;
}

export function PromptDiffViewer({ diff }: Props) {
  const { t } = useTranslation();
  return (
    <div className="border border-zinc-800 rounded-lg overflow-hidden">
      {/* Header */}
      <div className="flex items-center gap-4 px-4 py-2 bg-zinc-800/50 text-xs text-zinc-400 border-b border-zinc-800">
        <span>
          <span className="text-red-400">v{diff.versionA.version}</span>
          {diff.versionA.changeNote && (
            <span className="ml-1.5 text-zinc-500">({diff.versionA.changeNote})</span>
          )}
        </span>
        <span className="text-zinc-600">{t("prompts.diff.vs")}</span>
        <span>
          <span className="text-green-400">v{diff.versionB.version}</span>
          {diff.versionB.changeNote && (
            <span className="ml-1.5 text-zinc-500">({diff.versionB.changeNote})</span>
          )}
        </span>
      </div>

      {/* Diff lines */}
      <div className="overflow-auto max-h-[400px] font-mono text-xs">
        {diff.diffLines.map((line, i) => {
          let bg = "";
          let textColor = "text-zinc-300";
          let prefix = " ";

          if (line.lineType === "added") {
            bg = "bg-green-500/10";
            textColor = "text-green-300";
            prefix = "+";
          } else if (line.lineType === "removed") {
            bg = "bg-red-500/10";
            textColor = "text-red-300";
            prefix = "-";
          }

          return (
            <div key={i} className={`flex ${bg}`}>
              <span className="w-10 text-right pr-2 text-zinc-600 select-none border-r border-zinc-800/50 flex-shrink-0">
                {line.lineNumberA ?? ""}
              </span>
              <span className="w-10 text-right pr-2 text-zinc-600 select-none border-r border-zinc-800/50 flex-shrink-0">
                {line.lineNumberB ?? ""}
              </span>
              <span className={`w-4 text-center select-none flex-shrink-0 ${textColor}`}>
                {prefix}
              </span>
              <span className={`flex-1 px-2 py-0.5 whitespace-pre-wrap break-all ${textColor}`}>
                {line.content}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
