interface DiffHunk {
  header: string;
  lines: DiffLine[];
}

interface DiffLine {
  type: "added" | "removed" | "context";
  content: string;
  oldLineNo: number | null;
  newLineNo: number | null;
}

/** Detects if text contains a unified diff (--- a/file pattern). */
export function containsUnifiedDiff(text: string): boolean {
  return /^--- a\//m.test(text) && /^\+\+\+ b\//m.test(text);
}

/** Parses unified diff text into file-level hunks. */
function parseDiff(text: string): { file: string; hunks: DiffHunk[] }[] {
  const files: { file: string; hunks: DiffHunk[] }[] = [];
  const lines = text.split("\n");
  let i = 0;

  while (i < lines.length) {
    // Find --- a/file header
    if (lines[i]?.startsWith("--- a/")) {
      const fileName = lines[i].slice(6);
      i += 2; // skip +++ b/ line

      const hunks: DiffHunk[] = [];

      while (i < lines.length && !lines[i]?.startsWith("--- a/")) {
        if (lines[i]?.startsWith("@@")) {
          const header = lines[i];
          // Parse @@ -oldStart,oldCount +newStart,newCount @@
          const match = header.match(/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
          let oldLine = match ? parseInt(match[1]) : 1;
          let newLine = match ? parseInt(match[2]) : 1;
          i++;

          const hunkLines: DiffLine[] = [];
          while (i < lines.length && !lines[i]?.startsWith("@@") && !lines[i]?.startsWith("--- a/")) {
            const line = lines[i];
            if (line.startsWith("+")) {
              hunkLines.push({ type: "added", content: line.slice(1), oldLineNo: null, newLineNo: newLine++ });
            } else if (line.startsWith("-")) {
              hunkLines.push({ type: "removed", content: line.slice(1), oldLineNo: oldLine++, newLineNo: null });
            } else if (line.startsWith(" ") || line === "") {
              hunkLines.push({ type: "context", content: line.startsWith(" ") ? line.slice(1) : line, oldLineNo: oldLine++, newLineNo: newLine++ });
            } else {
              // Non-diff line (e.g. "\ No newline at end of file")
              i++;
              continue;
            }
            i++;
          }
          hunks.push({ header, lines: hunkLines });
        } else {
          i++;
        }
      }

      files.push({ file: fileName, hunks });
    } else {
      i++;
    }
  }

  return files;
}

interface Props {
  content: string;
}

export function CodeDiffViewer({ content }: Props) {
  const files = parseDiff(content);

  if (files.length === 0) return null;

  return (
    <div className="space-y-3">
      {files.map((file, fi) => (
        <div key={fi} className="border border-zinc-800 rounded-lg overflow-hidden">
          <div className="px-3 py-1.5 bg-zinc-800/60 text-xs text-zinc-300 font-mono border-b border-zinc-800">
            {file.file}
          </div>
          <div className="overflow-auto max-h-[500px] font-mono text-xs">
            {file.hunks.map((hunk, hi) => (
              <div key={hi}>
                <div className="px-3 py-1 bg-blue-500/5 text-blue-400 text-[10px] border-y border-zinc-800/50">
                  {hunk.header}
                </div>
                {hunk.lines.map((line, li) => {
                  const bg =
                    line.type === "added" ? "bg-green-500/10" :
                    line.type === "removed" ? "bg-red-500/10" : "";
                  const color =
                    line.type === "added" ? "text-green-300" :
                    line.type === "removed" ? "text-red-300" : "text-zinc-400";
                  const prefix =
                    line.type === "added" ? "+" :
                    line.type === "removed" ? "-" : " ";

                  return (
                    <div key={li} className={`flex ${bg}`}>
                      <span className="w-10 text-right pr-2 text-zinc-600 select-none border-r border-zinc-800/30 flex-shrink-0">
                        {line.oldLineNo ?? ""}
                      </span>
                      <span className="w-10 text-right pr-2 text-zinc-600 select-none border-r border-zinc-800/30 flex-shrink-0">
                        {line.newLineNo ?? ""}
                      </span>
                      <span className={`w-4 text-center select-none flex-shrink-0 ${color}`}>
                        {prefix}
                      </span>
                      <span className={`flex-1 px-2 py-px whitespace-pre ${color}`}>
                        {line.content}
                      </span>
                    </div>
                  );
                })}
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
