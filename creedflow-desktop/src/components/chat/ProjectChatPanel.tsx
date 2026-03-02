import { useEffect, useRef, useState } from "react";
import { X, Send, MessageCircle } from "lucide-react";
import { useChatStore } from "../../store/chatStore";
import { ChatMessage } from "./ChatMessage";
import { StreamingMessage } from "./StreamingMessage";
import { TaskProposalCard } from "./TaskProposalCard";

interface Props {
  projectId: string;
  projectName: string;
  onClose: () => void;
}

export function ProjectChatPanel({ projectId, projectName, onClose }: Props) {
  const {
    messages,
    isStreaming,
    streamingContent,
    error,
    loadMessages,
    sendMessage,
    clearError,
  } = useChatStore();

  const [input, setInput] = useState("");
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    loadMessages(projectId);
  }, [projectId, loadMessages]);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, isStreaming, streamingContent]);

  const handleSend = async () => {
    const trimmed = input.trim();
    if (!trimmed || isStreaming) return;
    setInput("");
    await sendMessage(projectId, trimmed);
    inputRef.current?.focus();
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const hasProposal = (metadata?: string) => {
    if (!metadata) return false;
    try {
      return JSON.parse(metadata)?.type === "task_proposal";
    } catch {
      return false;
    }
  };

  return (
    <div className="flex flex-col h-full border-r border-zinc-800 bg-zinc-900/50">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <div className="flex items-center gap-2">
          <MessageCircle className="w-4 h-4 text-amber-400" />
          <div>
            <div className="text-sm font-semibold text-zinc-200">
              Project Chat
            </div>
            <div className="text-[10px] text-zinc-500">{projectName}</div>
          </div>
        </div>
        <button
          onClick={onClose}
          className="p-1 rounded hover:bg-zinc-800 transition-colors"
        >
          <X className="w-4 h-4 text-zinc-500" />
        </button>
      </div>

      {/* Messages */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto">
        {messages.length === 0 && !isStreaming ? (
          <div className="flex flex-col items-center justify-center h-full px-6 text-center">
            <MessageCircle className="w-10 h-10 text-zinc-700 mb-3" />
            <div className="text-sm font-medium text-zinc-400 mb-1">
              Start a conversation
            </div>
            <div className="text-xs text-zinc-600 max-w-[240px]">
              Describe what you want to build and CreedFlow will propose tasks
              and features for your project.
            </div>
          </div>
        ) : (
          <div className="py-2">
            {messages.map((msg) => (
              <div key={msg.id}>
                <ChatMessage message={msg} />
                {hasProposal(msg.metadata) && (
                  <TaskProposalCard message={msg} />
                )}
              </div>
            ))}
            {isStreaming && <StreamingMessage content={streamingContent} />}
          </div>
        )}
      </div>

      {/* Error */}
      {error && (
        <div className="px-4 py-2 bg-red-500/10 border-t border-red-500/20">
          <div className="flex items-center justify-between">
            <span className="text-xs text-red-400">{error}</span>
            <button
              onClick={clearError}
              className="text-red-400 hover:text-red-300"
            >
              <X className="w-3 h-3" />
            </button>
          </div>
        </div>
      )}

      {/* Input */}
      <div className="border-t border-zinc-800 p-3">
        <div className="flex items-end gap-2">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Describe what you want to build..."
            rows={1}
            className="flex-1 resize-none bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:outline-none focus:border-amber-500/50 transition-colors"
            style={{ maxHeight: "120px" }}
          />
          <button
            onClick={handleSend}
            disabled={!input.trim() || isStreaming}
            className="flex-shrink-0 p-2 rounded-lg bg-amber-500 hover:bg-amber-600 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          >
            <Send className="w-4 h-4 text-zinc-900" />
          </button>
        </div>
      </div>
    </div>
  );
}
