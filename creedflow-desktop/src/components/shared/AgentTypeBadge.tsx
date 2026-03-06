import { useTranslation } from "react-i18next";
import type { AgentType } from "../../types/models";

const AGENT_LABEL_KEYS: Record<AgentType, string> = {
  analyzer: "agents.types.analyzer",
  coder: "agents.types.coder",
  reviewer: "agents.types.reviewer",
  tester: "agents.types.tester",
  devops: "agents.types.devops",
  monitor: "agents.types.monitor",
  contentWriter: "agents.types.contentWriter",
  designer: "agents.types.designer",
  imageGenerator: "agents.types.imageGen",
  videoEditor: "agents.types.videoEditor",
  publisher: "agents.types.publisher",
  planner: "agents.types.planner",
};

export function AgentTypeBadge({ agentType }: { agentType: AgentType }) {
  const { t } = useTranslation();
  const labelKey = AGENT_LABEL_KEYS[agentType];
  const label = labelKey ? t(labelKey) : agentType;
  return (
    <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-zinc-800 text-zinc-400">
      {label}
    </span>
  );
}
