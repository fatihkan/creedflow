import { useTranslation } from "react-i18next";
import { useThemeStore } from "../../store/themeStore";
import { Monitor, Sun, Moon } from "lucide-react";

const MODES = [
  { value: "system" as const, labelKey: "settings.theme.system", icon: Monitor },
  { value: "light" as const, labelKey: "settings.theme.light", icon: Sun },
  { value: "dark" as const, labelKey: "settings.theme.dark", icon: Moon },
];

export function ThemeToggle() {
  const { t } = useTranslation();
  const { mode, setMode } = useThemeStore();

  return (
    <div className="flex gap-1 bg-zinc-100 dark:bg-zinc-800 rounded-md p-0.5">
      {MODES.map(({ value, labelKey, icon: Icon }) => (
        <button
          key={value}
          onClick={() => setMode(value)}
          className={`flex items-center gap-1.5 px-3 py-1.5 text-xs rounded transition-colors ${
            mode === value
              ? "bg-white dark:bg-zinc-700 text-zinc-900 dark:text-zinc-200 shadow-sm"
              : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"
          }`}
        >
          <Icon className="w-3.5 h-3.5" />
          {t(labelKey)}
        </button>
      ))}
    </div>
  );
}
