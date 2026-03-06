import { describe, it, expect, vi, beforeEach } from "vitest";
import { useReviewStore } from "../store/reviewStore";
import type { Review } from "../types/models";

vi.mock("../tauri", () => ({
  listReviews: vi.fn(),
  approveReview: vi.fn(),
  rejectReview: vi.fn(),
  getPendingReviewCount: vi.fn(),
}));

import * as api from "../tauri";

const mockReview = (overrides: Partial<Review> = {}): Review => ({
  id: "r1",
  taskId: "t1",
  score: 8.0,
  verdict: "pass",
  summary: "Good code",
  issues: null,
  suggestions: null,
  securityNotes: null,
  sessionId: null,
  costUsd: null,
  isApproved: false,
  createdAt: "2024-01-01T00:00:00Z",
  ...overrides,
});

describe("reviewStore", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useReviewStore.setState({
      reviews: [],
      pendingCount: 0,
      loading: false,
      hasMore: true,
      pageSize: 50,
    });
  });

  it("starts with empty state", () => {
    const state = useReviewStore.getState();
    expect(state.reviews).toEqual([]);
    expect(state.pendingCount).toBe(0);
  });

  it("fetchReviews loads reviews", async () => {
    vi.mocked(api.listReviews).mockResolvedValue([mockReview()]);

    await useReviewStore.getState().fetchReviews();

    expect(api.listReviews).toHaveBeenCalledWith(50, 0);
    expect(useReviewStore.getState().reviews).toHaveLength(1);
    expect(useReviewStore.getState().loading).toBe(false);
  });

  it("fetchMoreReviews appends results", async () => {
    useReviewStore.setState({ reviews: [mockReview({ id: "r1" })] });
    vi.mocked(api.listReviews).mockResolvedValue([mockReview({ id: "r2" })]);

    await useReviewStore.getState().fetchMoreReviews();

    expect(api.listReviews).toHaveBeenCalledWith(50, 1);
    expect(useReviewStore.getState().reviews).toHaveLength(2);
  });

  it("fetchPendingCount updates count", async () => {
    vi.mocked(api.getPendingReviewCount).mockResolvedValue(7);

    await useReviewStore.getState().fetchPendingCount();

    expect(useReviewStore.getState().pendingCount).toBe(7);
  });

  it("approveReview sets isApproved and decrements pending", async () => {
    useReviewStore.setState({
      reviews: [mockReview({ id: "r1", isApproved: false })],
      pendingCount: 3,
    });
    vi.mocked(api.approveReview).mockResolvedValue(undefined);

    await useReviewStore.getState().approveReview("r1");

    expect(useReviewStore.getState().reviews[0].isApproved).toBe(true);
    expect(useReviewStore.getState().pendingCount).toBe(2);
  });

  it("rejectReview sets isApproved to false", async () => {
    useReviewStore.setState({
      reviews: [mockReview({ id: "r1", isApproved: true })],
    });
    vi.mocked(api.rejectReview).mockResolvedValue(undefined);

    await useReviewStore.getState().rejectReview("r1");

    expect(useReviewStore.getState().reviews[0].isApproved).toBe(false);
  });
});
