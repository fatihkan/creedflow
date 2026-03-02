import type { SidebarSection } from "./Sidebar";
import { ProjectList } from "../projects/ProjectList";
import { TaskBoard } from "../tasks/TaskBoard";
import { ArchivedTasksView } from "../tasks/ArchivedTasksView";
import { AgentStatus } from "../agents/AgentStatus";
import { SettingsDialog } from "../settings/SettingsDialog";
import { CostDashboard } from "../settings/CostDashboard";
import { DeployList } from "../deploy/DeployList";
import { ReviewList } from "../reviews/ReviewList";
import { GitGraphView } from "../git/GitGraphView";
import { PromptsLibrary } from "../prompts/PromptsLibrary";
import { ProjectAssetsView } from "../assets/ProjectAssetsView";

interface ContentAreaProps {
  section: SidebarSection;
  selectedProjectId: string | null;
  onToggleChat?: (projectId: string) => void;
  showChatPanel?: boolean;
  chatProjectId?: string | null;
}

export function ContentArea({
  section,
  selectedProjectId,
  onToggleChat,
  showChatPanel,
  chatProjectId,
}: ContentAreaProps) {
  switch (section) {
    case "projects":
      return <ProjectList />;
    case "tasks":
      return selectedProjectId ? (
        <TaskBoard
          projectId={selectedProjectId}
          onToggleChat={onToggleChat}
          showChatPanel={showChatPanel && chatProjectId === selectedProjectId}
        />
      ) : (
        <EmptyState message="Select a project to view tasks" />
      );
    case "archive":
      return <ArchivedTasksView />;
    case "agents":
      return <AgentStatus />;
    case "costs":
      return <CostDashboard />;
    case "reviews":
      return <ReviewList />;
    case "deploys":
      return <DeployList />;
    case "settings":
      return <SettingsDialog />;
    case "gitHistory":
      return selectedProjectId ? (
        <GitGraphView projectId={selectedProjectId} />
      ) : (
        <EmptyState message="Select a project to view git history" />
      );
    case "prompts":
      return <PromptsLibrary />;
    case "assets":
      return <ProjectAssetsView />;
    default:
      return <EmptyState message="Select a section" />;
  }
}

function EmptyState({ message }: { message: string }) {
  return (
    <div className="flex-1 flex items-center justify-center text-zinc-500 text-sm">
      {message}
    </div>
  );
}
