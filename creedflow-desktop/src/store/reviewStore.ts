import { create } from "zustand";
import type { Review } from "../types/models";
import * as api from "../tauri";

interface ReviewStore {
  reviews: Review[];
  pendingCount: number;
  loading: boolean;
  fetchReviews: () => Promise<void>;
  fetchPendingCount: () => Promise<void>;
  approveReview: (id: string) => Promise<void>;
  rejectReview: (id: string) => Promise<void>;
}

export const useReviewStore = create<ReviewStore>((set) => ({
  reviews: [],
  pendingCount: 0,
  loading: false,

  fetchReviews: async () => {
    set({ loading: true });
    try {
      const reviews = await api.listReviews();
      set({ reviews, loading: false });
    } catch (e) {
      console.error("Failed to fetch reviews:", e);
      set({ loading: false });
    }
  },

  fetchPendingCount: async () => {
    try {
      const pendingCount = await api.getPendingReviewCount();
      set({ pendingCount });
    } catch (e) {
      console.error("Failed to fetch pending review count:", e);
    }
  },

  approveReview: async (id) => {
    await api.approveReview(id);
    set((s) => ({
      reviews: s.reviews.map((r) =>
        r.id === id ? { ...r, isApproved: true } : r,
      ),
      pendingCount: Math.max(0, s.pendingCount - 1),
    }));
  },

  rejectReview: async (id) => {
    await api.rejectReview(id);
    set((s) => ({
      reviews: s.reviews.map((r) =>
        r.id === id ? { ...r, isApproved: false } : r,
      ),
    }));
  },
}));
