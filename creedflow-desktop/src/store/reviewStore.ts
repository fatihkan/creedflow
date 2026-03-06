import { create } from "zustand";
import type { Review } from "../types/models";
import { showErrorToast } from "../hooks/useErrorToast";
import * as api from "../tauri";

interface ReviewStore {
  reviews: Review[];
  pendingCount: number;
  loading: boolean;
  hasMore: boolean;
  pageSize: number;
  fetchReviews: () => Promise<void>;
  fetchMoreReviews: () => Promise<void>;
  fetchPendingCount: () => Promise<void>;
  approveReview: (id: string) => Promise<void>;
  rejectReview: (id: string) => Promise<void>;
}

export const useReviewStore = create<ReviewStore>((set, get) => ({
  reviews: [],
  pendingCount: 0,
  loading: false,
  hasMore: true,
  pageSize: 50,

  fetchReviews: async () => {
    set({ loading: true });
    try {
      const reviews = await api.listReviews(50, 0);
      set({ reviews, loading: false, hasMore: reviews.length >= 50 });
    } catch (e) {
      showErrorToast("Failed to fetch reviews", e);
      set({ loading: false });
    }
  },

  fetchMoreReviews: async () => {
    const { reviews, pageSize } = get();
    try {
      const more = await api.listReviews(pageSize, reviews.length);
      set((s) => ({
        reviews: [...s.reviews, ...more],
        hasMore: more.length >= pageSize,
      }));
    } catch (e) {
      showErrorToast("Failed to fetch more reviews", e);
    }
  },

  fetchPendingCount: async () => {
    try {
      const pendingCount = await api.getPendingReviewCount();
      set({ pendingCount });
    } catch (e) {
      showErrorToast("Failed to fetch pending review count", e);
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
