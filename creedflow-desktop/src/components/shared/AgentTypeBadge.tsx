import type { AgentType } from "../../types/models";

const AGENT_LABELS: Record<AgentType, string> = {
  analyzer: "Analyzer",
  coder: "Coder",
  reviewer: "Reviewer",
  tester: "Tester",
  devops: "DevOps",
  monitor: "Monitor",
  contentWriter: "Content Writer",
  designer: "Designer",
  imageGenerator: "Image Gen",
  videoEditor: "Video Editor",
  publisher: "Publisher",
};

export function AgentTypeBadge({ agentType }: { agentType: AgentType }) {
  const label = AGENT_LABELS[agentType] ?? agentType;
  return (
    <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-zinc-800 text-zinc-400">
      {label}
    </span>
  );
}
