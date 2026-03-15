import { useEffect, useState, useCallback } from "react";
import {
  Plus,
  Trash2,
  Power,
  PowerOff,
  Clock,
  Zap,
  ChevronDown,
  X,
  Save,
  Filter,
} from "lucide-react";
import type {
  AutomationFlow,
  AutomationTrigger,
  AutomationAction,
} from "../../types/models";
import {
  listAutomationFlows,
  createAutomationFlow,
  updateAutomationFlow,
  deleteAutomationFlow,
  toggleAutomationFlow,
} from "../../tauri";

const TRIGGER_TYPES: { value: AutomationTrigger; label: string }[] = [
  { value: "task_completed", label: "Task Completed" },
  { value: "task_failed", label: "Task Failed" },
  { value: "deploy_success", label: "Deploy Success" },
  { value: "deploy_failed", label: "Deploy Failed" },
  { value: "review_passed", label: "Review Passed" },
  { value: "review_failed", label: "Review Failed" },
  { value: "schedule", label: "Schedule" },
];

const ACTION_TYPES: { value: AutomationAction; label: string }[] = [
  { value: "create_task", label: "Create Task" },
  { value: "send_notification", label: "Send Notification" },
  { value: "run_command", label: "Run Command" },
  { value: "deploy", label: "Deploy" },
];

const TRIGGER_COLORS: Record<AutomationTrigger, string> = {
  task_completed: "bg-green-500/20 text-green-400",
  task_failed: "bg-red-500/20 text-red-400",
  deploy_success: "bg-emerald-500/20 text-emerald-400",
  deploy_failed: "bg-orange-500/20 text-orange-400",
  review_passed: "bg-blue-500/20 text-blue-400",
  review_failed: "bg-amber-500/20 text-amber-400",
  schedule: "bg-purple-500/20 text-purple-400",
};

const ACTION_COLORS: Record<AutomationAction, string> = {
  create_task: "bg-cyan-500/20 text-cyan-400",
  send_notification: "bg-yellow-500/20 text-yellow-400",
  run_command: "bg-pink-500/20 text-pink-400",
  deploy: "bg-indigo-500/20 text-indigo-400",
};

interface FlowEditorState {
  mode: "create" | "edit";
  id?: string;
  projectId: string | null;
  name: string;
  triggerType: AutomationTrigger;
  triggerConfig: string;
  actionType: AutomationAction;
  actionConfig: string;
  isEnabled: boolean;
}

const emptyEditor: FlowEditorState = {
  mode: "create",
  projectId: null,
  name: "",
  triggerType: "task_completed",
  triggerConfig: "{}",
  actionType: "create_task",
  actionConfig: "{}",
  isEnabled: true,
};

export function AutomationFlowsPanel() {
  const [flows, setFlows] = useState<AutomationFlow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editor, setEditor] = useState<FlowEditorState | null>(null);
  const [filterTrigger, setFilterTrigger] = useState<AutomationTrigger | "all">("all");
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);

  const fetchFlows = useCallback(async () => {
    try {
      setLoading(true);
      const data = await listAutomationFlows();
      setFlows(data);
      setError(null);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchFlows();
  }, [fetchFlows]);

  const handleToggle = async (id: string) => {
    try {
      await toggleAutomationFlow(id);
      await fetchFlows();
    } catch (e) {
      setError(String(e));
    }
  };

  const handleDelete = async (id: string) => {
    try {
      await deleteAutomationFlow(id);
      setConfirmDelete(null);
      await fetchFlows();
    } catch (e) {
      setError(String(e));
    }
  };

  const handleSave = async () => {
    if (!editor) return;
    try {
      if (editor.mode === "create") {
        await createAutomationFlow({
          projectId: editor.projectId,
          name: editor.name,
          triggerType: editor.triggerType,
          triggerConfig: editor.triggerConfig,
          actionType: editor.actionType,
          actionConfig: editor.actionConfig,
          isEnabled: editor.isEnabled,
        });
      } else if (editor.id) {
        await updateAutomationFlow(editor.id, {
          projectId: editor.projectId,
          name: editor.name,
          triggerType: editor.triggerType,
          triggerConfig: editor.triggerConfig,
          actionType: editor.actionType,
          actionConfig: editor.actionConfig,
          isEnabled: editor.isEnabled,
        });
      }
      setEditor(null);
      await fetchFlows();
    } catch (e) {
      setError(String(e));
    }
  };

  const openEditFlow = (flow: AutomationFlow) => {
    setEditor({
      mode: "edit",
      id: flow.id,
      projectId: flow.projectId,
      name: flow.name,
      triggerType: flow.triggerType,
      triggerConfig: flow.triggerConfig,
      actionType: flow.actionType,
      actionConfig: flow.actionConfig,
      isEnabled: flow.isEnabled,
    });
  };

  const filteredFlows =
    filterTrigger === "all"
      ? flows
      : flows.filter((f) => f.triggerType === filterTrigger);

  const triggerLabel = (t: AutomationTrigger) =>
    TRIGGER_TYPES.find((x) => x.value === t)?.label ?? t;
  const actionLabel = (a: AutomationAction) =>
    ACTION_TYPES.find((x) => x.value === a)?.label ?? a;

  return (
    <div className="flex-1 flex flex-col h-full bg-zinc-950">
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-zinc-800">
        <div>
          <h2 className="text-sm font-semibold text-zinc-200">Automation Flows</h2>
          <p className="text-xs text-zinc-500 mt-0.5">
            Define trigger-action flows that execute automatically
          </p>
        </div>
        <div className="flex items-center gap-2">
          {/* Filter */}
          <div className="relative">
            <select
              value={filterTrigger}
              onChange={(e) => setFilterTrigger(e.target.value as AutomationTrigger | "all")}
              className="appearance-none bg-zinc-800 border border-zinc-700 text-zinc-300 text-xs rounded-md pl-7 pr-6 py-1.5 focus:outline-none focus:ring-1 focus:ring-brand-500"
            >
              <option value="all">All Triggers</option>
              {TRIGGER_TYPES.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
            <Filter className="absolute left-2 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-zinc-500" />
            <ChevronDown className="absolute right-1.5 top-1/2 -translate-y-1/2 w-3 h-3 text-zinc-500" />
          </div>

          <button
            onClick={() => setEditor({ ...emptyEditor })}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-brand-600/20 text-brand-400 text-xs font-medium rounded-md hover:bg-brand-600/30 transition-colors"
          >
            <Plus className="w-3.5 h-3.5" />
            New Flow
          </button>
        </div>
      </div>

      {/* Error banner */}
      {error && (
        <div className="mx-6 mt-3 px-3 py-2 bg-red-500/10 border border-red-500/20 rounded-md text-xs text-red-400 flex items-center justify-between">
          <span>{error}</span>
          <button onClick={() => setError(null)} className="text-red-400 hover:text-red-300">
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {/* Editor */}
      {editor && (
        <div className="mx-6 mt-4 p-4 bg-zinc-900 border border-zinc-700 rounded-lg">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-xs font-semibold text-zinc-300">
              {editor.mode === "create" ? "New Automation Flow" : "Edit Flow"}
            </h3>
            <button
              onClick={() => setEditor(null)}
              className="text-zinc-500 hover:text-zinc-300"
            >
              <X className="w-4 h-4" />
            </button>
          </div>

          <div className="space-y-3">
            {/* Name */}
            <div>
              <label className="block text-[11px] font-medium text-zinc-400 mb-1">Name</label>
              <input
                type="text"
                value={editor.name}
                onChange={(e) => setEditor({ ...editor, name: e.target.value })}
                placeholder="e.g. Auto-review on coder completion"
                className="w-full bg-zinc-800 border border-zinc-700 text-zinc-200 text-xs rounded-md px-3 py-1.5 focus:outline-none focus:ring-1 focus:ring-brand-500"
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              {/* Trigger Type */}
              <div>
                <label className="block text-[11px] font-medium text-zinc-400 mb-1">
                  Trigger
                </label>
                <select
                  value={editor.triggerType}
                  onChange={(e) =>
                    setEditor({
                      ...editor,
                      triggerType: e.target.value as AutomationTrigger,
                    })
                  }
                  className="w-full bg-zinc-800 border border-zinc-700 text-zinc-300 text-xs rounded-md px-3 py-1.5 focus:outline-none focus:ring-1 focus:ring-brand-500"
                >
                  {TRIGGER_TYPES.map((t) => (
                    <option key={t.value} value={t.value}>
                      {t.label}
                    </option>
                  ))}
                </select>
              </div>

              {/* Action Type */}
              <div>
                <label className="block text-[11px] font-medium text-zinc-400 mb-1">
                  Action
                </label>
                <select
                  value={editor.actionType}
                  onChange={(e) =>
                    setEditor({
                      ...editor,
                      actionType: e.target.value as AutomationAction,
                    })
                  }
                  className="w-full bg-zinc-800 border border-zinc-700 text-zinc-300 text-xs rounded-md px-3 py-1.5 focus:outline-none focus:ring-1 focus:ring-brand-500"
                >
                  {ACTION_TYPES.map((a) => (
                    <option key={a.value} value={a.value}>
                      {a.label}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
              {/* Trigger Config */}
              <div>
                <label className="block text-[11px] font-medium text-zinc-400 mb-1">
                  Trigger Config (JSON)
                </label>
                <textarea
                  value={editor.triggerConfig}
                  onChange={(e) => setEditor({ ...editor, triggerConfig: e.target.value })}
                  placeholder='{"agentType": "coder"}'
                  rows={3}
                  className="w-full bg-zinc-800 border border-zinc-700 text-zinc-300 text-xs rounded-md px-3 py-1.5 font-mono focus:outline-none focus:ring-1 focus:ring-brand-500 resize-none"
                />
              </div>

              {/* Action Config */}
              <div>
                <label className="block text-[11px] font-medium text-zinc-400 mb-1">
                  Action Config (JSON)
                </label>
                <textarea
                  value={editor.actionConfig}
                  onChange={(e) => setEditor({ ...editor, actionConfig: e.target.value })}
                  placeholder='{"agentType": "reviewer", "title": "Auto-review"}'
                  rows={3}
                  className="w-full bg-zinc-800 border border-zinc-700 text-zinc-300 text-xs rounded-md px-3 py-1.5 font-mono focus:outline-none focus:ring-1 focus:ring-brand-500 resize-none"
                />
              </div>
            </div>

            {/* Enabled toggle */}
            <label className="flex items-center gap-2 text-xs text-zinc-400 cursor-pointer">
              <input
                type="checkbox"
                checked={editor.isEnabled}
                onChange={(e) => setEditor({ ...editor, isEnabled: e.target.checked })}
                className="rounded border-zinc-600 bg-zinc-800 text-brand-500 focus:ring-brand-500"
              />
              Enabled
            </label>

            {/* Actions */}
            <div className="flex justify-end gap-2 pt-1">
              <button
                onClick={() => setEditor(null)}
                className="px-3 py-1.5 text-xs text-zinc-400 hover:text-zinc-200 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleSave}
                disabled={!editor.name.trim()}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-brand-600/20 text-brand-400 text-xs font-medium rounded-md hover:bg-brand-600/30 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <Save className="w-3.5 h-3.5" />
                {editor.mode === "create" ? "Create" : "Save"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Flow list */}
      <div className="flex-1 overflow-y-auto p-6 space-y-2">
        {loading ? (
          <div className="text-center text-zinc-500 text-xs py-12">Loading...</div>
        ) : filteredFlows.length === 0 ? (
          <div className="text-center py-16">
            <Zap className="w-8 h-8 text-zinc-700 mx-auto mb-3" />
            <p className="text-sm text-zinc-500">No automation flows yet</p>
            <p className="text-xs text-zinc-600 mt-1">
              Create your first flow to automate workflows
            </p>
          </div>
        ) : (
          filteredFlows.map((flow) => (
            <div
              key={flow.id}
              className={`group flex items-center gap-3 px-4 py-3 rounded-lg border transition-colors cursor-pointer ${
                flow.isEnabled
                  ? "bg-zinc-900/60 border-zinc-800 hover:border-zinc-700"
                  : "bg-zinc-900/30 border-zinc-800/50 opacity-60"
              }`}
              onClick={() => openEditFlow(flow)}
            >
              {/* Toggle */}
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  handleToggle(flow.id);
                }}
                className={`flex-shrink-0 ${
                  flow.isEnabled
                    ? "text-green-400 hover:text-green-300"
                    : "text-zinc-600 hover:text-zinc-400"
                }`}
                title={flow.isEnabled ? "Disable" : "Enable"}
              >
                {flow.isEnabled ? (
                  <Power className="w-4 h-4" />
                ) : (
                  <PowerOff className="w-4 h-4" />
                )}
              </button>

              {/* Name & badges */}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-xs font-medium text-zinc-200 truncate">
                    {flow.name}
                  </span>
                </div>
                <div className="flex items-center gap-1.5 mt-1">
                  <span
                    className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium ${
                      TRIGGER_COLORS[flow.triggerType]
                    }`}
                  >
                    {triggerLabel(flow.triggerType)}
                  </span>
                  <span className="text-zinc-600 text-[10px]">→</span>
                  <span
                    className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium ${
                      ACTION_COLORS[flow.actionType]
                    }`}
                  >
                    {actionLabel(flow.actionType)}
                  </span>
                </div>
              </div>

              {/* Last triggered */}
              {flow.lastTriggeredAt && (
                <div className="flex items-center gap-1 text-[10px] text-zinc-600 flex-shrink-0">
                  <Clock className="w-3 h-3" />
                  <span>
                    {new Date(flow.lastTriggeredAt).toLocaleDateString()}
                  </span>
                </div>
              )}

              {/* Scope badge */}
              <span
                className={`flex-shrink-0 text-[10px] px-1.5 py-0.5 rounded ${
                  flow.projectId
                    ? "bg-zinc-800 text-zinc-400"
                    : "bg-brand-600/15 text-brand-400"
                }`}
              >
                {flow.projectId ? "Project" : "Global"}
              </span>

              {/* Delete */}
              <div className="flex-shrink-0" onClick={(e) => e.stopPropagation()}>
                {confirmDelete === flow.id ? (
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => handleDelete(flow.id)}
                      className="text-[10px] px-2 py-0.5 bg-red-500/20 text-red-400 rounded hover:bg-red-500/30"
                    >
                      Confirm
                    </button>
                    <button
                      onClick={() => setConfirmDelete(null)}
                      className="text-[10px] px-2 py-0.5 text-zinc-500 hover:text-zinc-300"
                    >
                      Cancel
                    </button>
                  </div>
                ) : (
                  <button
                    onClick={() => setConfirmDelete(flow.id)}
                    className="text-zinc-600 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all"
                    title="Delete"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>
            </div>
          ))
        )}
      </div>

      {/* Footer stats */}
      <div className="px-6 py-2 border-t border-zinc-800 flex items-center justify-between text-[10px] text-zinc-600">
        <span>
          {flows.length} flow{flows.length !== 1 ? "s" : ""} total, {flows.filter((f) => f.isEnabled).length} enabled
        </span>
        <span>
          {filteredFlows.length !== flows.length && `Showing ${filteredFlows.length} of ${flows.length}`}
        </span>
      </div>
    </div>
  );
}
