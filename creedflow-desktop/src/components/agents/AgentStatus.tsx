import { useEffect, useState } from "react";
import { useAgentStore } from "../../store/agentStore";
import { useProjectStore } from "../../store/projectStore";
import { useTaskStore } from "../../store/taskStore";
import { Cpu, Clock, Shield, Activity } from "lucide-react";
import { SearchBar } from "../shared/SearchBar";
import { Skeleton } from "../shared/Skeleton";
import { useTranslation } from "react-i18next";

export function AgentStatus() {
  const { t } = useTranslation();
  const { agentTypes, fetchAgentTypes } = useAgentStore();
  const tasks = useTaskStore((s) => s.tasks);
  const projects = useProjectStore((s) => s.projects);
  const [search, setSearch] = useState("");

  useEffect(() => {
    fetchAgentTypes();
  }, [fetchAgentTypes]);

  const activeTasks = tasks.filter((t) => t.status === "in_progress");
  const recentCompleted = tasks
    .filter((t) => t.status === "passed" || t.status === "failed")
    .slice(0, 5);

  // Count tasks per agent type from current tasks
  const taskCountByAgent: Record<string, number> = {};
  tasks.forEach((t) => {
    taskCountByAgent[t.agentType] = (taskCountByAgent[t.agentType] || 0) + 1;
  });

  const filteredAgents = search.trim()
    ? agentTypes.filter((a) => {
        const q = search.toLowerCase();
        return (
          a.displayName.toLowerCase().includes(q) ||
          a.agentType.toLowerCase().includes(q) ||
          a.backendPreference.toLowerCase().includes(q)
        );
      })
    : agentTypes;

  return (
    <div className="flex-1 flex flex-col">
      <div className="px-4 py-3 border-b border-zinc-800">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-sm font-semibold text-zinc-200">{t("agents.title")}</h2>
            <p className="text-xs text-zinc-500 mt-0.5">{t("agents.configured", { count: agentTypes.length })}</p>
          </div>
          <div className="flex items-center gap-2">
            <SearchBar
              value={search}
              onChange={setSearch}
              placeholder={t("agents.searchPlaceholder")}
            />
            {activeTasks.length > 0 && (
              <span className="flex items-center gap-1.5 text-xs bg-blue-500/15 text-blue-400 px-2.5 py-1 rounded-full">
                <Activity className="w-3 h-3" />
                {t("agents.active", { count: activeTasks.length })}
              </span>
            )}
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-6">
        {/* Active tasks */}
        {activeTasks.length > 0 && (
          <section>
            <h3 className="text-[10px] font-semibold text-zinc-500 uppercase tracking-wider mb-2">
              {t("agents.activeRunners")}
            </h3>
            <div className="space-y-1.5">
              {activeTasks.map((task) => {
                const project = projects.find((p) => p.id === task.projectId);
                return (
                  <div
                    key={task.id}
                    className="flex items-center gap-3 px-3 py-2 bg-blue-500/5 border border-blue-500/15 rounded-md"
                  >
                    <div className="w-2 h-2 rounded-full bg-blue-500 animate-pulse" />
                    <div className="flex-1 min-w-0">
                      <p className="text-xs text-zinc-200 truncate">{task.title}</p>
                      <p className="text-[10px] text-zinc-500">
                        {task.agentType} {task.backend ? `· ${task.backend}` : ""}
                        {project ? ` · ${project.name}` : ""}
                      </p>
                    </div>
                  </div>
                );
              })}
            </div>
          </section>
        )}

        {/* Agent cards */}
        <section>
          <h3 className="text-[10px] font-semibold text-zinc-500 uppercase tracking-wider mb-2">
            {t("agents.agentTypes")}
          </h3>
          <div className="grid grid-cols-2 gap-3">
            {filteredAgents.length === 0 && !search ? (
              <>
                {[1, 2, 3, 4].map((i) => (
                  <div key={i} className="p-3 rounded-lg border border-zinc-800 bg-zinc-900/50 space-y-2">
                    <Skeleton className="h-4 w-24" />
                    <div className="flex gap-2">
                      <Skeleton className="h-3 w-12" />
                      <Skeleton className="h-3 w-16" />
                    </div>
                  </div>
                ))}
              </>
            ) : filteredAgents.map((agent) => {
              const count = taskCountByAgent[agent.agentType] || 0;
              const isActive = activeTasks.some((t) => t.agentType === agent.agentType);
              return (
                <div
                  key={agent.agentType}
                  className={`p-3 rounded-lg border transition-colors ${
                    isActive
                      ? "bg-blue-500/5 border-blue-500/20"
                      : "bg-zinc-900/50 border-zinc-800"
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <h3 className="text-sm font-medium text-zinc-200">
                      {agent.displayName}
                    </h3>
                    <div className="flex items-center gap-1">
                      {isActive && (
                        <div className="w-2 h-2 rounded-full bg-blue-500 animate-pulse" />
                      )}
                      <span
                        className={`text-[10px] px-1.5 py-0.5 rounded ${
                          agent.hasMcp
                            ? "bg-purple-900/50 text-purple-400"
                            : "bg-zinc-800 text-zinc-500"
                        }`}
                      >
                        {agent.hasMcp ? "MCP" : "CLI"}
                      </span>
                    </div>
                  </div>
                  <div className="flex items-center gap-3 mt-2 text-[10px] text-zinc-500">
                    <span className="flex items-center gap-1">
                      <Clock className="w-3 h-3" />
                      {agent.timeoutSeconds}s
                    </span>
                    <span className="flex items-center gap-1">
                      <Cpu className="w-3 h-3" />
                      {agent.backendPreference}
                    </span>
                    {count > 0 && (
                      <span className="flex items-center gap-1 text-zinc-400">
                        <Shield className="w-3 h-3" />
                        {count} tasks
                      </span>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </section>

        {/* Recent completed tasks */}
        {recentCompleted.length > 0 && (
          <section>
            <h3 className="text-[10px] font-semibold text-zinc-500 uppercase tracking-wider mb-2">
              {t("agents.recentCompleted")}
            </h3>
            <div className="space-y-1">
              {recentCompleted.map((task) => (
                <div
                  key={task.id}
                  className="flex items-center justify-between px-3 py-1.5 bg-zinc-800/30 rounded"
                >
                  <div className="flex items-center gap-2 min-w-0">
                    <div className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${
                      task.status === "passed" ? "bg-green-500" : "bg-red-500"
                    }`} />
                    <span className="text-xs text-zinc-300 truncate">{task.title}</span>
                  </div>
                  <span className="text-[10px] text-zinc-600 flex-shrink-0 ml-2">
                    {task.agentType}
                  </span>
                </div>
              ))}
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
