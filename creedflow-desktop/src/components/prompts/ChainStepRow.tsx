import { useState, useRef } from "react";
import { GripVertical, Trash2, ChevronDown, ChevronRight } from "lucide-react";
import type { PromptChainStep, ChainCondition } from "../../types/models";
import { useTranslation } from "react-i18next";

const CONDITION_FIELDS: ChainCondition["field"][] = [
  "reviewScore",
  "reviewVerdict",
  "outputContains",
  "stepSuccess",
];

const FIELD_LABELS: Record<ChainCondition["field"], string> = {
  reviewScore: "Review Score",
  reviewVerdict: "Review Verdict",
  outputContains: "Output Contains",
  stepSuccess: "Step Success",
};

const OPERATORS_BY_FIELD: Record<ChainCondition["field"], ChainCondition["op"][]> = {
  reviewScore: ["eq", "neq", "gt", "gte", "lt", "lte"],
  reviewVerdict: ["eq", "neq"],
  outputContains: ["contains", "notContains"],
  stepSuccess: ["eq"],
};

const OP_LABELS: Record<ChainCondition["op"], string> = {
  eq: "=",
  neq: "!=",
  gt: ">",
  gte: ">=",
  lt: "<",
  lte: "<=",
  contains: "contains",
  notContains: "not contains",
};

interface ChainStepRowProps {
  step: PromptChainStep;
  index: number;
  promptTitle: string;
  allStepOrders: number[];
  onRemove: () => void;
  onDragStart: () => void;
  onDragOver: (e: React.DragEvent) => void;
  onDrop: () => void;
  isDragging: boolean;
  onTransitionNoteBlur: (value: string) => void;
  onConditionChange: (condition: string | null, onFailStepOrder: number | null) => void;
}

function parseCondition(json: string | null): ChainCondition | null {
  if (!json) return null;
  try {
    return JSON.parse(json) as ChainCondition;
  } catch {
    return null;
  }
}

export function ChainStepRow({
  step,
  index,
  promptTitle,
  allStepOrders,
  onRemove,
  onDragStart,
  onDragOver,
  onDrop,
  isDragging,
  onTransitionNoteBlur,
  onConditionChange,
}: ChainStepRowProps) {
  const { t } = useTranslation();
  const [note, setNote] = useState(step.transitionNote ?? "");
  const noteRef = useRef<HTMLInputElement>(null);

  const existingCondition = parseCondition(step.condition);
  const [showCondition, setShowCondition] = useState(!!existingCondition);
  const [field, setField] = useState<ChainCondition["field"]>(existingCondition?.field ?? "reviewScore");
  const [op, setOp] = useState<ChainCondition["op"]>(existingCondition?.op ?? "gte");
  const [value, setValue] = useState<string>(
    existingCondition ? String(existingCondition.value) : "7"
  );
  const [failTarget, setFailTarget] = useState<string>(
    step.onFailStepOrder != null ? String(step.onFailStepOrder) : ""
  );

  const availableOps = OPERATORS_BY_FIELD[field] ?? ["eq"];

  const commitCondition = (
    newField: ChainCondition["field"],
    newOp: ChainCondition["op"],
    newValue: string,
    newFailTarget: string,
    enabled: boolean,
  ) => {
    if (!enabled) {
      onConditionChange(null, null);
      return;
    }
    let parsedValue: number | string | boolean;
    if (newField === "reviewScore") {
      parsedValue = parseFloat(newValue) || 0;
    } else if (newField === "stepSuccess") {
      parsedValue = newValue === "true";
    } else {
      parsedValue = newValue;
    }
    const condition: ChainCondition = { field: newField, op: newOp, value: parsedValue };
    const failOrder = newFailTarget ? parseInt(newFailTarget, 10) : null;
    onConditionChange(JSON.stringify(condition), isNaN(failOrder as number) ? null : failOrder);
  };

  return (
    <div
      draggable
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDrop={onDrop}
      className={`bg-zinc-800/40 rounded-md transition-opacity ${
        isDragging ? "opacity-50" : ""
      }`}
    >
      <div className="flex items-center gap-2 px-3 py-2 cursor-grab active:cursor-grabbing">
        <GripVertical className="w-3 h-3 text-zinc-600 flex-shrink-0" />
        <span className="text-[10px] text-zinc-500 w-5 flex-shrink-0">
          {index + 1}.
        </span>
        <span className="text-xs text-zinc-300 flex-1 truncate">{promptTitle}</span>
        {step.condition && (
          <span className="text-[9px] px-1.5 py-0.5 bg-amber-600/20 text-amber-400 rounded">
            conditional
          </span>
        )}
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
          onClick={() => {
            const next = !showCondition;
            setShowCondition(next);
            if (!next) commitCondition(field, op, value, failTarget, false);
          }}
          className={`p-0.5 rounded transition-colors flex-shrink-0 ${
            showCondition
              ? "bg-amber-600/20 text-amber-400 hover:bg-amber-600/30"
              : "hover:bg-zinc-700 text-zinc-500 hover:text-zinc-300"
          }`}
          title="Toggle condition"
        >
          {showCondition ? (
            <ChevronDown className="w-3 h-3" />
          ) : (
            <ChevronRight className="w-3 h-3" />
          )}
        </button>
        <button
          onClick={onRemove}
          className="p-0.5 rounded hover:bg-zinc-700 text-zinc-500 hover:text-red-400 transition-colors flex-shrink-0"
          aria-label="Remove step"
        >
          <Trash2 className="w-3 h-3" />
        </button>
      </div>

      {showCondition && (
        <div className="px-3 pb-2 pt-1 border-t border-zinc-700/30 space-y-1.5">
          <div className="flex items-center gap-2 flex-wrap">
            <label className="text-[10px] text-zinc-500 w-8">If</label>
            <select
              className="text-[10px] bg-zinc-900 border border-zinc-700/50 rounded px-1.5 py-0.5 text-zinc-300"
              value={field}
              onChange={(e) => {
                const f = e.target.value as ChainCondition["field"];
                const ops = OPERATORS_BY_FIELD[f];
                const newOp = ops.includes(op) ? op : ops[0];
                setField(f);
                setOp(newOp);
                commitCondition(f, newOp, value, failTarget, true);
              }}
            >
              {CONDITION_FIELDS.map((f) => (
                <option key={f} value={f}>{FIELD_LABELS[f]}</option>
              ))}
            </select>
            <select
              className="text-[10px] bg-zinc-900 border border-zinc-700/50 rounded px-1.5 py-0.5 text-zinc-300"
              value={op}
              onChange={(e) => {
                const o = e.target.value as ChainCondition["op"];
                setOp(o);
                commitCondition(field, o, value, failTarget, true);
              }}
            >
              {availableOps.map((o) => (
                <option key={o} value={o}>{OP_LABELS[o]}</option>
              ))}
            </select>
            {field === "stepSuccess" ? (
              <select
                className="text-[10px] bg-zinc-900 border border-zinc-700/50 rounded px-1.5 py-0.5 text-zinc-300 w-16"
                value={value}
                onChange={(e) => {
                  setValue(e.target.value);
                  commitCondition(field, op, e.target.value, failTarget, true);
                }}
              >
                <option value="true">true</option>
                <option value="false">false</option>
              </select>
            ) : (
              <input
                type={field === "reviewScore" ? "number" : "text"}
                className="text-[10px] bg-zinc-900 border border-zinc-700/50 rounded px-1.5 py-0.5 text-zinc-300 w-20"
                value={value}
                onChange={(e) => setValue(e.target.value)}
                onBlur={() => commitCondition(field, op, value, failTarget, true)}
                step={field === "reviewScore" ? "0.1" : undefined}
              />
            )}
          </div>
          <div className="flex items-center gap-2">
            <label className="text-[10px] text-zinc-500 whitespace-nowrap">On fail</label>
            <select
              className="text-[10px] bg-zinc-900 border border-zinc-700/50 rounded px-1.5 py-0.5 text-zinc-300 flex-1"
              value={failTarget}
              onChange={(e) => {
                setFailTarget(e.target.value);
                commitCondition(field, op, value, e.target.value, true);
              }}
            >
              <option value="">Fail chain</option>
              {allStepOrders
                .filter((o) => o !== step.stepOrder)
                .map((o) => (
                  <option key={o} value={String(o)}>Jump to step {o + 1}</option>
                ))}
            </select>
          </div>
        </div>
      )}
    </div>
  );
}
