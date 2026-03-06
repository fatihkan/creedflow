import { create } from "zustand";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type { ChatAttachment, ProjectMessage } from "../types/models";
import {
  sendChatMessage,
  streamChatResponse,
  listChatMessages,
  approveChatProposal,
  rejectChatProposal,
} from "../tauri";

interface ChatStreamEvent {
  type: "chunk" | "done" | "error";
  projectId: string;
  content?: string;
  messageId?: string;
  backend?: string;
  costUsd?: number;
  message?: string;
}

interface ChatState {
  messages: ProjectMessage[];
  isStreaming: boolean;
  streamingContent: string;
  error: string | null;
  pendingAttachments: ChatAttachment[];

  loadMessages: (projectId: string) => Promise<void>;
  sendMessage: (projectId: string, content: string) => Promise<void>;
  approveProposal: (messageId: string, metadata: string) => Promise<void>;
  rejectProposal: (messageId: string) => Promise<void>;
  addAttachment: (attachment: ChatAttachment) => void;
  removeAttachment: (path: string) => void;
  clearAttachments: () => void;
  clearMessages: () => void;
  clearError: () => void;
}

export const useChatStore = create<ChatState>((set, get) => ({
  messages: [],
  isStreaming: false,
  streamingContent: "",
  error: null,
  pendingAttachments: [],

  loadMessages: async (projectId: string) => {
    try {
      const messages = await listChatMessages(projectId);
      set({ messages, error: null });
    } catch (e) {
      set({ error: String(e) });
    }
  },

  sendMessage: async (projectId: string, content: string) => {
    let unlisten: UnlistenFn | null = null;
    try {
      set({ error: null });
      const attachments = get().pendingAttachments;

      // Save user message to DB
      const userMsg = await sendChatMessage(
        projectId,
        content,
        "user",
        attachments.length > 0 ? attachments : undefined,
      );
      set((s) => ({
        messages: [...s.messages, userMsg],
        isStreaming: true,
        streamingContent: "",
        pendingAttachments: [],
      }));

      // Listen for streaming events

      unlisten = await listen<ChatStreamEvent>("chat-stream", (event) => {
        const data = event.payload;
        if (data.projectId !== projectId) return;

        switch (data.type) {
          case "chunk":
            set((s) => ({
              streamingContent: s.streamingContent + (data.content ?? ""),
            }));
            break;

          case "done": {
            const assistantMsg: ProjectMessage = {
              id: data.messageId ?? "",
              projectId,
              role: "assistant",
              content: get().streamingContent,
              backend: data.backend,
              costUsd: data.costUsd,
              createdAt: new Date().toISOString(),
            };
            set((s) => ({
              messages: [...s.messages, assistantMsg],
              isStreaming: false,
              streamingContent: "",
            }));
            unlisten?.();
            break;
          }

          case "error":
            set({
              error: data.message ?? "Unknown error",
              isStreaming: false,
              streamingContent: "",
            });
            unlisten?.();
            break;
        }
      });

      // Trigger the backend to start streaming
      await streamChatResponse(projectId, content, attachments);
    } catch (e) {
      unlisten?.();
      set({ error: String(e), isStreaming: false, streamingContent: "" });
    }
  },

  approveProposal: async (messageId: string, metadata: string) => {
    try {
      await approveChatProposal(messageId, metadata);
      set((s) => ({
        messages: s.messages.map((m) =>
          m.id === messageId ? { ...m, metadata } : m,
        ),
      }));
    } catch (e) {
      set({ error: String(e) });
    }
  },

  rejectProposal: async (messageId: string) => {
    try {
      await rejectChatProposal(messageId);
      set((s) => ({
        messages: s.messages.map((m) =>
          m.id === messageId
            ? { ...m, metadata: '{"status":"rejected"}' }
            : m,
        ),
      }));
    } catch (e) {
      set({ error: String(e) });
    }
  },

  addAttachment: (attachment: ChatAttachment) => {
    set((s) => {
      if (s.pendingAttachments.some((a) => a.path === attachment.path)) return s;
      return { pendingAttachments: [...s.pendingAttachments, attachment] };
    });
  },

  removeAttachment: (path: string) => {
    set((s) => ({
      pendingAttachments: s.pendingAttachments.filter((a) => a.path !== path),
    }));
  },

  clearAttachments: () => set({ pendingAttachments: [] }),
  clearMessages: () => set({ messages: [] }),
  clearError: () => set({ error: null }),
}));
