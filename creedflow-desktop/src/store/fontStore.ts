import { create } from "zustand";

type FontSize = "small" | "normal" | "large";

const SCALE_MAP: Record<FontSize, number> = {
  small: 0.9,
  normal: 1.0,
  large: 1.15,
};

interface FontStore {
  size: FontSize;
  setSize: (size: FontSize) => void;
  initialize: () => void;
}

function applyScale(size: FontSize) {
  const scale = SCALE_MAP[size];
  document.documentElement.style.setProperty("--font-scale", String(scale));
}

export const useFontStore = create<FontStore>((set) => ({
  size: (localStorage.getItem("creedflow_font_size") as FontSize) || "normal",

  setSize: (size) => {
    localStorage.setItem("creedflow_font_size", size);
    applyScale(size);
    set({ size });
  },

  initialize: () => {
    const size = (localStorage.getItem("creedflow_font_size") as FontSize) || "normal";
    applyScale(size);
    set({ size });
  },
}));
