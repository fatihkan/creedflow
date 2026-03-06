import { useState, useRef } from "react";
import { GripVertical, Trash2 } from "lucide-react";
import type { PromptChainStep } from "../../types/models";
import { useTranslation } from "react-i18next";

interface ChainStepRowProps {
  step: PromptChainStep;
  index: number;
  promptTitle: string;
  onRemove: () => void;
  onDragStart: () => void;
  onDragOver: (e: React.DragEvent) => void;
  onDrop: () => void;
  isDragging: boolean;
  onTransitionNoteBlur: (value: string) => void;
}

export function ChainStepRow({
  step,
  index,
  promptTitle,
  onRemove,
  onDragStart,
  onDragOver,
  onDrop,
  isDragging,
  onTransitionNoteBlur,
}: ChainStepRowProps) {
  const { t } = useTranslation();
  const [note, setNote] = useState(step.transitionNote ?? "");
  const noteRef = useRef<HTMLInputElement>(null);

  return (
    <div
      draggable
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDrop={onDrop}
      className={`flex items-center gap-2 px-3 py-2 bg-zinc-800/40 rounded-md cursor-grab active:cursor-grabbing transition-opacity ${
        isDragging ? "opacity-50" : ""
      }`}
    >
      <GripVertical className="w-3 h-3 text-zinc-600 flex-shrink-0" />
      <span className="text-[10px] text-zinc-500 w-5 flex-shrink-0">
        {index + 1}.
      </span>
      <span className="text-xs text-zinc-300 flex-1 truncate">{promptTitle}</span>
      <input
        ref={noteRef}
        type="text"
        value={note}
        onChange={(e) => setNote(e.target.value)}
        onBlur={() => onTransitionNoteBlur(note)}
        placeholder={t("prompts.chains.transitionNotePlaceholder")}
        className="w-[140px] px-2 py-0.5 text-[10px] bg-zinc-900 border border-zinc-700/50 rounded text-zinc-400 placeholder:text-zinc-600 focus:outline-none focus:border-brand-500"
      />
      <button
        onClick={onRemove}
        className="p-0.5 rounded hover:bg-zinc-700 text-zinc-500 hover:text-red-400 transition-colors flex-shrink-0"
        aria-label="Remove step"
      >
        <Trash2 className="w-3 h-3" />
      </button>
    </div>
  );
}
