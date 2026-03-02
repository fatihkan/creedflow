import { Bot, Loader2 } from "lucide-react";

interface Props {
  content: string;
}

export function StreamingMessage({ content }: Props) {
  return (
    <div className="flex gap-3 px-4 py-3">
      <div className="flex-shrink-0 w-7 h-7 rounded-full bg-zinc-700 flex items-center justify-center">
        <Bot className="w-3.5 h-3.5 text-zinc-400" />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-1">
          <span className="text-xs font-medium text-zinc-400">
            CreedFlow AI
          </span>
          <Loader2 className="w-3 h-3 text-amber-400 animate-spin" />
        </div>
        {content ? (
          <div className="inline-block text-sm leading-relaxed whitespace-pre-wrap rounded-lg px-3 py-2 bg-zinc-800 text-zinc-300">
            {content}
            <span className="inline-block w-1.5 h-4 bg-amber-400 animate-pulse ml-0.5 align-middle" />
          </div>
        ) : (
          <div className="flex items-center gap-1.5 px-3 py-2">
            <span className="w-1.5 h-1.5 bg-zinc-500 rounded-full animate-bounce [animation-delay:0ms]" />
            <span className="w-1.5 h-1.5 bg-zinc-500 rounded-full animate-bounce [animation-delay:150ms]" />
            <span className="w-1.5 h-1.5 bg-zinc-500 rounded-full animate-bounce [animation-delay:300ms]" />
          </div>
        )}
      </div>
    </div>
  );
}
