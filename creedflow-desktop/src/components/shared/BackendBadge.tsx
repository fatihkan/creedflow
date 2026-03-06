import { useTranslation } from "react-i18next";

const BACKEND_COLORS: Record<string, { bg: string; text: string }> = {
  claude: { bg: "bg-purple-900/50", text: "text-purple-400" },
  codex: { bg: "bg-green-900/50", text: "text-green-400" },
  gemini: { bg: "bg-blue-900/50", text: "text-blue-400" },
  ollama: { bg: "bg-orange-900/50", text: "text-orange-400" },
  lmStudio: { bg: "bg-cyan-900/50", text: "text-cyan-400" },
  llamaCpp: { bg: "bg-pink-900/50", text: "text-pink-400" },
  mlx: { bg: "bg-lime-900/50", text: "text-lime-400" },
};

const BACKEND_NAME_KEYS: Record<string, string> = {
  claude: "common.backends.claude",
  codex: "common.backends.codex",
  gemini: "common.backends.gemini",
  ollama: "common.backends.ollama",
  lmStudio: "common.backends.lmstudio",
  llamaCpp: "common.backends.llamacpp",
  mlx: "common.backends.mlx",
};

export function BackendBadge({ backend }: { backend: string | null }) {
  const { t } = useTranslation();
  if (!backend) return null;
  const colors = BACKEND_COLORS[backend] ?? {
    bg: "bg-zinc-700",
    text: "text-zinc-300",
  };
  const nameKey = BACKEND_NAME_KEYS[backend];
  const name = nameKey ? t(nameKey) : backend;
  return (
    <span
      className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium ${colors.bg} ${colors.text}`}
    >
      {name}
    </span>
  );
}
