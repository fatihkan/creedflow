import type { SidebarSection } from "./Sidebar";
import { ProjectList } from "../projects/ProjectList";
import { TaskBoard } from "../tasks/TaskBoard";
import { ArchivedTasksView } from "../tasks/ArchivedTasksView";
import { AgentStatus } from "../agents/AgentStatus";
import { SettingsDialog } from "../settings/SettingsDialog";
import { CostDashboard } from "../settings/CostDashboard";
import { DeployList } from "../deploy/DeployList";
import { ReviewList } from "../reviews/ReviewList";

interface ContentAreaProps {
  section: SidebarSection;
  selectedProjectId: string | null;
}

export function ContentArea({ section, selectedProjectId }: ContentAreaProps) {
  switch (section) {
    case "projects":
      return <ProjectList />;
    case "tasks":
      return selectedProjectId ? (
        <TaskBoard projectId={selectedProjectId} />
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
        <EmptyState message="Git history view — coming soon" />
      ) : (
        <EmptyState message="Select a project to view git history" />
      );
    case "prompts":
      return <EmptyState message="Prompt library coming soon" />;
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
