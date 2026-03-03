import { create } from "zustand";

type ThemeMode = "system" | "light" | "dark";

interface ThemeStore {
  mode: ThemeMode;
  setMode: (mode: ThemeMode) => void;
}

function applyTheme(mode: ThemeMode) {
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const isDark = mode === "dark" || (mode === "system" && prefersDark);
  document.documentElement.classList.toggle("dark", isDark);
}

function getStoredMode(): ThemeMode {
  const stored = localStorage.getItem("creedflow-theme");
  if (stored === "light" || stored === "dark" || stored === "system") {
    return stored;
  }
  return "dark";
}

export const useThemeStore = create<ThemeStore>((set) => {
  const initial = getStoredMode();
  applyTheme(initial);

  // Listen for system theme changes
  window
    .matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", () => {
      const current = useThemeStore.getState().mode;
      if (current === "system") {
        applyTheme("system");
      }
    });

  return {
    mode: initial,
    setMode: (mode) => {
      localStorage.setItem("creedflow-theme", mode);
      applyTheme(mode);
      set({ mode });
    },
  };
});
