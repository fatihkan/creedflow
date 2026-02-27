import { Star, Trash2, Copy, Check } from "lucide-react";
import { useState } from "react";
import type { Prompt } from "../../store/promptStore";

interface PromptCardProps {
  prompt: Prompt;
  onToggleFavorite: () => void;
  onDelete: () => void;
}

export function PromptCard({ prompt, onToggleFavorite, onDelete }: PromptCardProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(prompt.content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="bg-zinc-800/50 border border-zinc-800 rounded-lg p-3 hover:border-zinc-700 transition-colors group">
      {/* Header */}
      <div className="flex items-start justify-between gap-2">
        <h3 className="text-xs font-medium text-zinc-200 line-clamp-1 flex-1">
          {prompt.title}
        </h3>
        <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
          <button
            onClick={handleCopy}
            className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-zinc-300"
            title="Copy content"
          >
            {copied ? (
              <Check className="w-3 h-3 text-green-400" />
            ) : (
              <Copy className="w-3 h-3" />
            )}
          </button>
          <button
            onClick={onToggleFavorite}
            className="p-1 rounded hover:bg-zinc-700"
            title="Toggle favorite"
          >
            <Star
              className={`w-3 h-3 ${
                prompt.isFavorite
                  ? "text-amber-400 fill-amber-400"
                  : "text-zinc-500"
              }`}
            />
          </button>
          {!prompt.isBuiltIn && (
            <button
              onClick={onDelete}
              className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-red-400"
              title="Delete"
            >
              <Trash2 className="w-3 h-3" />
            </button>
          )}
        </div>
      </div>

      {/* Content preview */}
      <p className="text-[11px] text-zinc-400 mt-1.5 line-clamp-3 leading-relaxed">
        {prompt.content}
      </p>

      {/* Footer */}
      <div className="flex items-center gap-1.5 mt-2">
        <span className="text-[10px] bg-zinc-900 text-zinc-500 px-1.5 py-0.5 rounded">
          {prompt.category}
        </span>
        <span className="text-[10px] text-zinc-600">
          {prompt.source === "user" ? "Custom" : "Built-in"}
        </span>
        {prompt.isFavorite && (
          <Star className="w-2.5 h-2.5 text-amber-400 fill-amber-400 ml-auto" />
        )}
      </div>
    </div>
  );
}
