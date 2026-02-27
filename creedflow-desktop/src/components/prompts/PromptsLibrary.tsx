import { useEffect, useState } from "react";
import { usePromptStore } from "../../store/promptStore";
import { PromptCard } from "./PromptCard";
import { PromptEditDialog } from "./PromptEditDialog";
import { Plus, Search, Star, BookOpen } from "lucide-react";

const CATEGORIES = [
  "All",
  "coding",
  "review",
  "testing",
  "analysis",
  "content",
  "design",
  "devops",
  "general",
];

export function PromptsLibrary() {
  const { prompts, loading, filter, fetchPrompts, setFilter, filteredPrompts, deletePrompt, toggleFavorite } =
    usePromptStore();
  const [showCreate, setShowCreate] = useState(false);
  const [tab, setTab] = useState<"library" | "chains" | "effectiveness">("library");

  useEffect(() => {
    fetchPrompts();
  }, [fetchPrompts]);

  const filtered = filteredPrompts();

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <div className="flex items-center gap-2">
          <BookOpen className="w-4 h-4 text-zinc-400" />
          <h2 className="text-sm font-medium text-zinc-200">Prompts Library</h2>
          <span className="text-xs text-zinc-500">({prompts.length})</span>
        </div>
        <button
          onClick={() => setShowCreate(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded transition-colors"
        >
          <Plus className="w-3.5 h-3.5" />
          New Prompt
        </button>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-zinc-800">
        {(["library", "chains", "effectiveness"] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2 text-xs font-medium capitalize transition-colors ${
              tab === t
                ? "text-brand-400 border-b-2 border-brand-400"
                : "text-zinc-500 hover:text-zinc-300"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === "library" && (
        <>
          {/* Filters */}
          <div className="flex items-center gap-2 px-4 py-2 border-b border-zinc-800/50">
            {/* Search */}
            <div className="relative flex-1 max-w-[240px]">
              <Search className="absolute left-2 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-zinc-500" />
              <input
                type="text"
                value={filter.search}
                onChange={(e) => setFilter({ search: e.target.value })}
                placeholder="Search prompts..."
                className="w-full pl-7 pr-3 py-1.5 text-xs bg-zinc-800 border border-zinc-700 rounded text-zinc-300 placeholder-zinc-600 focus:outline-none focus:border-brand-500"
              />
            </div>

            {/* Category */}
            <div className="flex gap-1">
              {CATEGORIES.map((cat) => (
                <button
                  key={cat}
                  onClick={() =>
                    setFilter({ category: cat === "All" ? null : cat })
                  }
                  className={`px-2 py-1 text-[10px] rounded transition-colors ${
                    (cat === "All" && !filter.category) ||
                    filter.category === cat
                      ? "bg-brand-600/20 text-brand-400"
                      : "bg-zinc-800 text-zinc-500 hover:text-zinc-300"
                  }`}
                >
                  {cat}
                </button>
              ))}
            </div>

            {/* Favorites toggle */}
            <button
              onClick={() => setFilter({ favoritesOnly: !filter.favoritesOnly })}
              className={`p-1.5 rounded transition-colors ${
                filter.favoritesOnly
                  ? "bg-amber-900/30 text-amber-400"
                  : "bg-zinc-800 text-zinc-500 hover:text-zinc-300"
              }`}
              title="Show favorites only"
            >
              <Star className="w-3.5 h-3.5" />
            </button>
          </div>

          {/* Grid */}
          <div className="flex-1 overflow-y-auto p-4">
            {loading ? (
              <div className="flex items-center justify-center h-32 text-zinc-500 text-sm">
                Loading...
              </div>
            ) : filtered.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-32 text-zinc-500 text-sm">
                <p>No prompts found</p>
                <button
                  onClick={() => setShowCreate(true)}
                  className="mt-2 text-xs text-brand-400 hover:underline"
                >
                  Create your first prompt
                </button>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                {filtered.map((prompt) => (
                  <PromptCard
                    key={prompt.id}
                    prompt={prompt}
                    onToggleFavorite={() => toggleFavorite(prompt.id)}
                    onDelete={() => deletePrompt(prompt.id)}
                  />
                ))}
              </div>
            )}
          </div>
        </>
      )}

      {tab === "chains" && (
        <div className="flex-1 flex items-center justify-center text-zinc-500 text-sm">
          Prompt chains — coming soon
        </div>
      )}

      {tab === "effectiveness" && (
        <div className="flex-1 flex items-center justify-center text-zinc-500 text-sm">
          Effectiveness tracking — coming soon
        </div>
      )}

      {/* Create dialog */}
      {showCreate && <PromptEditDialog onClose={() => setShowCreate(false)} />}
    </div>
  );
}
