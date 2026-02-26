import { useEffect, useState } from "react";
import { useReviewStore } from "../../store/reviewStore";
import { Check, X, ChevronDown, ChevronUp, FileCheck } from "lucide-react";
import type { Review } from "../../types/models";

type FilterType = "all" | "pending" | "approved";

function scoreColor(score: number): string {
  if (score >= 7) return "text-green-400";
  if (score >= 5) return "text-amber-400";
  return "text-red-400";
}

function verdictBadge(verdict: Review["verdict"]) {
  const styles: Record<string, string> = {
    pass: "bg-green-500/20 text-green-400",
    needsRevision: "bg-amber-500/20 text-amber-400",
    fail: "bg-red-500/20 text-red-400",
  };
  const labels: Record<string, string> = {
    pass: "Pass",
    needsRevision: "Needs Revision",
    fail: "Fail",
  };
  return (
    <span
      className={`px-1.5 py-0.5 text-[10px] rounded ${styles[verdict] || "bg-zinc-700 text-zinc-400"}`}
    >
      {labels[verdict] || verdict}
    </span>
  );
}

export function ReviewList() {
  const { reviews, loading, fetchReviews, approveReview, rejectReview } =
    useReviewStore();
  const [filter, setFilter] = useState<FilterType>("all");
  const [expandedId, setExpandedId] = useState<string | null>(null);

  useEffect(() => {
    fetchReviews();
  }, [fetchReviews]);

  const filtered = reviews.filter((r) => {
    if (filter === "pending") return !r.isApproved;
    if (filter === "approved") return r.isApproved;
    return true;
  });

  return (
    <div className="flex-1 flex flex-col">
      <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
        <div>
          <h2 className="text-sm font-semibold text-zinc-200">Reviews</h2>
          <p className="text-xs text-zinc-500 mt-0.5">
            {filtered.length} review{filtered.length !== 1 ? "s" : ""}
          </p>
        </div>
        <div className="flex gap-1">
          {(["all", "pending", "approved"] as FilterType[]).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-2.5 py-1 text-[10px] rounded-md capitalize ${
                filter === f
                  ? "bg-brand-600/20 text-brand-400"
                  : "text-zinc-500 hover:text-zinc-300"
              }`}
            >
              {f}
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center h-full text-zinc-500 text-sm">
            Loading...
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-zinc-500">
            <FileCheck className="w-8 h-8 mb-2 opacity-50" />
            <p className="text-sm">No reviews found</p>
          </div>
        ) : (
          <div className="p-4 space-y-2">
            {filtered.map((review) => {
              const isExpanded = expandedId === review.id;
              return (
                <div
                  key={review.id}
                  className="bg-zinc-800/50 border border-zinc-800 rounded-md overflow-hidden"
                >
                  <div
                    className="flex items-center justify-between p-3 cursor-pointer hover:bg-zinc-800/80"
                    onClick={() =>
                      setExpandedId(isExpanded ? null : review.id)
                    }
                  >
                    <div className="flex items-center gap-2 flex-1 min-w-0">
                      <span
                        className={`text-sm font-bold tabular-nums ${scoreColor(review.score)}`}
                      >
                        {review.score.toFixed(1)}
                      </span>
                      {verdictBadge(review.verdict)}
                      <span className="text-xs text-zinc-400 truncate">
                        {review.summary.slice(0, 80)}
                        {review.summary.length > 80 ? "..." : ""}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      {review.isApproved ? (
                        <span className="text-[10px] text-green-500">
                          Approved
                        </span>
                      ) : (
                        <div className="flex gap-1">
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              approveReview(review.id);
                            }}
                            className="p-1 text-green-500 hover:bg-green-500/20 rounded"
                            title="Approve"
                          >
                            <Check className="w-3.5 h-3.5" />
                          </button>
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              rejectReview(review.id);
                            }}
                            className="p-1 text-red-500 hover:bg-red-500/20 rounded"
                            title="Reject"
                          >
                            <X className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      )}
                      {isExpanded ? (
                        <ChevronUp className="w-4 h-4 text-zinc-500" />
                      ) : (
                        <ChevronDown className="w-4 h-4 text-zinc-500" />
                      )}
                    </div>
                  </div>

                  {isExpanded && (
                    <div className="px-3 pb-3 space-y-2 border-t border-zinc-800/50">
                      <div className="pt-2">
                        <label className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
                          Summary
                        </label>
                        <p className="text-xs text-zinc-300 mt-1">
                          {review.summary}
                        </p>
                      </div>
                      {review.issues && (
                        <div>
                          <label className="text-[10px] font-medium text-red-500 uppercase tracking-wider">
                            Issues
                          </label>
                          <p className="text-xs text-zinc-400 mt-1 whitespace-pre-wrap">
                            {review.issues}
                          </p>
                        </div>
                      )}
                      {review.suggestions && (
                        <div>
                          <label className="text-[10px] font-medium text-blue-500 uppercase tracking-wider">
                            Suggestions
                          </label>
                          <p className="text-xs text-zinc-400 mt-1 whitespace-pre-wrap">
                            {review.suggestions}
                          </p>
                        </div>
                      )}
                      {review.securityNotes && (
                        <div>
                          <label className="text-[10px] font-medium text-amber-500 uppercase tracking-wider">
                            Security Notes
                          </label>
                          <p className="text-xs text-zinc-400 mt-1 whitespace-pre-wrap">
                            {review.securityNotes}
                          </p>
                        </div>
                      )}
                      <div className="flex items-center gap-3 text-[10px] text-zinc-600">
                        <span>
                          {new Date(review.createdAt).toLocaleString()}
                        </span>
                        {review.costUsd != null && (
                          <span>${review.costUsd.toFixed(4)}</span>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
