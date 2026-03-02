import { create } from "zustand";
import type { ProjectMessage } from "../types/models";
import {
  sendChatMessage,
  listChatMessages,
  approveChatProposal,
  rejectChatProposal,
} from "../tauri";

interface ChatState {
  messages: ProjectMessage[];
  isStreaming: boolean;
  streamingContent: string;
  error: string | null;

  loadMessages: (projectId: string) => Promise<void>;
  sendMessage: (projectId: string, content: string) => Promise<void>;
  approveProposal: (messageId: string, metadata: string) => Promise<void>;
  rejectProposal: (messageId: string) => Promise<void>;
  clearMessages: () => void;
  clearError: () => void;
}

export const useChatStore = create<ChatState>((set) => ({
  messages: [],
  isStreaming: false,
  streamingContent: "",
  error: null,

  loadMessages: async (projectId: string) => {
    try {
      const messages = await listChatMessages(projectId);
      set({ messages, error: null });
    } catch (e) {
      set({ error: String(e) });
    }
  },

  sendMessage: async (projectId: string, content: string) => {
    try {
      set({ error: null });
      // Save user message
      const userMsg = await sendChatMessage(projectId, content, "user");
      set((s) => ({ messages: [...s.messages, userMsg] }));

      // Save a placeholder assistant response
      // In a real implementation, this would stream from the backend
      set({ isStreaming: true, streamingContent: "" });

      const assistantMsg = await sendChatMessage(
        projectId,
        "I've received your message. The AI chat backend will process this when connected to an active CLI backend.",
        "assistant",
      );
      set((s) => ({
        messages: [...s.messages, assistantMsg],
        isStreaming: false,
        streamingContent: "",
      }));
    } catch (e) {
      set({ error: String(e), isStreaming: false });
    }
  },

  approveProposal: async (messageId: string, metadata: string) => {
    try {
      await approveChatProposal(messageId, metadata);
      // Update the message metadata locally
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

  clearMessages: () => set({ messages: [] }),
  clearError: () => set({ error: null }),
}));
