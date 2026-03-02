import { Bot, User } from "lucide-react";
import type { ProjectMessage } from "../../types/models";

interface Props {
  message: ProjectMessage;
}

const BACKEND_COLORS: Record<string, string> = {
  claude: "bg-purple-500/20 text-purple-300",
  codex: "bg-green-500/20 text-green-300",
  gemini: "bg-blue-500/20 text-blue-300",
  ollama: "bg-orange-500/20 text-orange-300",
  lmStudio: "bg-cyan-500/20 text-cyan-300",
  llamaCpp: "bg-pink-500/20 text-pink-300",
  mlx: "bg-teal-500/20 text-teal-300",
};

export function ChatMessage({ message }: Props) {
  const isUser = message.role === "user";
  const isSystem = message.role === "system";

  if (isSystem) {
    return (
      <div className="flex justify-center px-4 py-2">
        <span className="text-xs text-zinc-500 italic">{message.content}</span>
      </div>
    );
  }

  return (
    <div
      className={`flex gap-3 px-4 py-3 ${isUser ? "flex-row-reverse" : ""}`}
    >
      {/* Avatar */}
      <div
        className={`flex-shrink-0 w-7 h-7 rounded-full flex items-center justify-center ${
          isUser ? "bg-amber-500/20" : "bg-zinc-700"
        }`}
      >
        {isUser ? (
          <User className="w-3.5 h-3.5 text-amber-400" />
        ) : (
          <Bot className="w-3.5 h-3.5 text-zinc-400" />
        )}
      </div>

      {/* Content */}
      <div className={`flex-1 min-w-0 ${isUser ? "text-right" : ""}`}>
        <div className="flex items-center gap-2 mb-1">
          <span className="text-xs font-medium text-zinc-400">
            {isUser ? "You" : "CreedFlow AI"}
          </span>
          {message.backend && (
            <span
              className={`text-[10px] font-medium px-1.5 py-0.5 rounded ${
                BACKEND_COLORS[message.backend] ?? "bg-zinc-700 text-zinc-300"
              }`}
            >
              {message.backend}
            </span>
          )}
          <span className="text-[10px] text-zinc-600">
            {new Date(message.createdAt).toLocaleTimeString([], {
              hour: "2-digit",
              minute: "2-digit",
            })}
          </span>
        </div>
        <div
          className={`inline-block text-sm leading-relaxed whitespace-pre-wrap rounded-lg px-3 py-2 ${
            isUser
              ? "bg-amber-500/10 text-zinc-200"
              : "bg-zinc-800 text-zinc-300"
          }`}
        >
          {message.content}
        </div>
      </div>
    </div>
  );
}
