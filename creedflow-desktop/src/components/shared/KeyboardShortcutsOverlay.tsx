import { useEffect } from "react";
import { X } from "lucide-react";
import { FocusTrap } from "./FocusTrap";
import { useTranslation } from "react-i18next";

interface Props {
  open: boolean;
  onClose: () => void;
}

export function KeyboardShortcutsOverlay({ open, onClose }: Props) {
  const { t } = useTranslation();

  const SHORTCUT_GROUPS = [
    {
      title: t("shortcuts.navigation"),
      shortcuts: [
        { keys: ["Cmd", "1"], description: t("shortcuts.projects") },
        { keys: ["Cmd", "2"], description: t("shortcuts.tasks") },
        { keys: ["Cmd", "3"], description: t("shortcuts.agents") },
        { keys: ["Cmd", "4"], description: t("shortcuts.reviews") },
        { keys: ["Cmd", "5"], description: t("shortcuts.deploy") },
        { keys: ["Cmd", "6"], description: t("shortcuts.prompts") },
        { keys: ["Cmd", "7"], description: t("shortcuts.assets") },
        { keys: ["Cmd", "8"], description: t("shortcuts.gitHistory") },
      ],
    },
    {
      title: t("shortcuts.actions"),
      shortcuts: [
        { keys: ["Escape"], description: t("shortcuts.closePanel") },
        { keys: ["Cmd", "?"], description: t("shortcuts.showOverlay") },
      ],
    },
  ];
  useEffect(() => {
    if (!open) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
        onClose();
      }
    };
    window.addEventListener("keydown", handleKeyDown, true);
    return () => window.removeEventListener("keydown", handleKeyDown, true);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 bg-black/60 flex items-center justify-center z-50"
      role="dialog"
      aria-modal="true"
      aria-labelledby="shortcuts-title"
      onClick={onClose}
    >
      <FocusTrap>
      <div
        className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-700 rounded-lg w-[400px] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-200 dark:border-zinc-800">
          <h2 id="shortcuts-title" className="text-sm font-semibold text-zinc-900 dark:text-zinc-200">
            {t("shortcuts.title")}
          </h2>
          <button
            onClick={onClose}
            className="p-1 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 rounded"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="px-5 py-4 space-y-5">
          {SHORTCUT_GROUPS.map((group) => (
            <div key={group.title}>
              <h3 className="text-[10px] font-semibold text-zinc-500 uppercase tracking-wider mb-2">
                {group.title}
              </h3>
              <div className="space-y-1.5">
                {group.shortcuts.map((shortcut) => (
                  <div
                    key={shortcut.description}
                    className="flex items-center justify-between"
                  >
                    <span className="text-xs text-zinc-600 dark:text-zinc-400">
                      {shortcut.description}
                    </span>
                    <div className="flex items-center gap-1">
                      {shortcut.keys.map((key) => (
                        <kbd
                          key={key}
                          className="px-1.5 py-0.5 text-[10px] font-mono bg-zinc-100 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded text-zinc-600 dark:text-zinc-400"
                        >
                          {key === "Cmd" ? "\u2318" : key}
                        </kbd>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
      </FocusTrap>
    </div>
  );
}
