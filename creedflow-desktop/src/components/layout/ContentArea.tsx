import type { SidebarSection } from "./Sidebar";
import { ProjectList } from "../projects/ProjectList";
import { TaskBoard } from "../tasks/TaskBoard";
import { AgentStatus } from "../agents/AgentStatus";
import { SettingsDialog } from "../settings/SettingsDialog";
import { CostDashboard } from "../settings/CostDashboard";

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
    case "agents":
      return <AgentStatus />;
    case "costs":
      return <CostDashboard />;
    case "reviews":
      return <EmptyState message="Reviews will appear here" />;
    case "deploys":
      return <EmptyState message="Deployment management coming soon" />;
    case "settings":
      return <SettingsDialog />;
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
