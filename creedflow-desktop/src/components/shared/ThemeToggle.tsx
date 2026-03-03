import { useThemeStore } from "../../store/themeStore";
import { Monitor, Sun, Moon } from "lucide-react";

const MODES = [
  { value: "system" as const, label: "System", icon: Monitor },
  { value: "light" as const, label: "Light", icon: Sun },
  { value: "dark" as const, label: "Dark", icon: Moon },
];

export function ThemeToggle() {
  const { mode, setMode } = useThemeStore();

  return (
    <div className="flex gap-1 bg-zinc-100 dark:bg-zinc-800 rounded-md p-0.5">
      {MODES.map(({ value, label, icon: Icon }) => (
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
          {label}
        </button>
      ))}
    </div>
  );
}
