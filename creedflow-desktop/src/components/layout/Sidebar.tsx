import {
  FolderKanban,
  LayoutDashboard,
  Bot,
  DollarSign,
  FileCheck,
  Rocket,
  Settings,
  BookOpen,
} from "lucide-react";

export type SidebarSection =
  | "projects"
  | "tasks"
  | "agents"
  | "costs"
  | "reviews"
  | "deploys"
  | "settings"
  | "prompts";

interface SidebarProps {
  selected: SidebarSection;
  onSelect: (section: SidebarSection) => void;
}

const SECTIONS: { id: SidebarSection; label: string; icon: React.FC<{ className?: string }> }[] = [
  { id: "projects", label: "Projects", icon: FolderKanban },
  { id: "tasks", label: "Tasks", icon: LayoutDashboard },
  { id: "agents", label: "Agents", icon: Bot },
  { id: "costs", label: "Costs", icon: DollarSign },
  { id: "reviews", label: "Reviews", icon: FileCheck },
  { id: "deploys", label: "Deploy", icon: Rocket },
  { id: "prompts", label: "Prompts", icon: BookOpen },
  { id: "settings", label: "Settings", icon: Settings },
];

export function Sidebar({ selected, onSelect }: SidebarProps) {
  return (
    <aside className="w-[200px] min-w-[180px] max-w-[280px] bg-zinc-900/50 border-r border-zinc-800 flex flex-col">
      {/* App title */}
      <div className="h-12 flex items-center px-4 border-b border-zinc-800">
        <h1 className="text-sm font-bold text-brand-400 tracking-wider">
          CREEDFLOW
        </h1>
      </div>

      {/* Navigation */}
      <nav className="flex-1 py-2 px-2 space-y-0.5 overflow-y-auto">
        {SECTIONS.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => onSelect(id)}
            className={`w-full flex items-center gap-2.5 px-3 py-2 rounded-md text-sm transition-colors ${
              selected === id
                ? "bg-brand-600/20 text-brand-400"
                : "text-zinc-400 hover:text-zinc-200 hover:bg-zinc-800/50"
            }`}
          >
            <Icon className="w-4 h-4 flex-shrink-0" />
            {label}
          </button>
        ))}
      </nav>

      {/* Version */}
      <div className="px-4 py-3 border-t border-zinc-800">
        <span className="text-[10px] text-zinc-600">v0.1.0</span>
      </div>
    </aside>
  );
}
