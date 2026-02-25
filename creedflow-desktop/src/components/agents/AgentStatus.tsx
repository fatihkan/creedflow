import { useEffect } from "react";
import { useAgentStore } from "../../store/agentStore";

export function AgentStatus() {
  const { agentTypes, fetchAgentTypes } = useAgentStore();

  useEffect(() => {
    fetchAgentTypes();
  }, [fetchAgentTypes]);

  return (
    <div className="flex-1 flex flex-col">
      <div className="px-4 py-3 border-b border-zinc-800">
        <h2 className="text-sm font-semibold text-zinc-200">Agents</h2>
        <p className="text-xs text-zinc-500 mt-0.5">11 agent types configured</p>
      </div>

      <div className="flex-1 overflow-y-auto p-4">
        <div className="grid grid-cols-2 gap-3">
          {agentTypes.map((agent) => (
            <div
              key={agent.agentType}
              className="p-3 bg-zinc-900/50 rounded-lg border border-zinc-800"
            >
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-medium text-zinc-200">
                  {agent.displayName}
                </h3>
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
              <div className="flex items-center gap-3 mt-2 text-[10px] text-zinc-500">
                <span>Timeout: {agent.timeoutSeconds}s</span>
                <span>Pref: {agent.backendPreference}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
