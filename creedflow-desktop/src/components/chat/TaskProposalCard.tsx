import { Check, X, ListTodo } from "lucide-react";
import type { ProjectMessage, TaskProposal } from "../../types/models";
import { useChatStore } from "../../store/chatStore";

interface Props {
  message: ProjectMessage;
}

function parseProposal(metadata?: string): TaskProposal | null {
  if (!metadata) return null;
  try {
    const parsed = JSON.parse(metadata);
    if (parsed.type === "task_proposal" && parsed.features) {
      return parsed as TaskProposal;
    }
  } catch {
    // not a proposal
  }
  return null;
}

export function TaskProposalCard({ message }: Props) {
  const proposal = parseProposal(message.metadata);
  const approveProposal = useChatStore((s) => s.approveProposal);
  const rejectProposal = useChatStore((s) => s.rejectProposal);

  if (!proposal) return null;

  const isApproved = proposal.status === "approved";
  const isRejected = proposal.status === "rejected";
  const isPending = !isApproved && !isRejected;

  return (
    <div className="mx-4 my-2 border border-zinc-700 rounded-lg overflow-hidden">
      {/* Header */}
      <div className="flex items-center gap-2 px-3 py-2 bg-zinc-800/50 border-b border-zinc-700">
        <ListTodo className="w-4 h-4 text-amber-400" />
        <span className="text-xs font-semibold text-zinc-300">
          Task Proposal
        </span>
        {isApproved && (
          <span className="ml-auto text-[10px] font-medium text-green-400 bg-green-500/10 px-1.5 py-0.5 rounded">
            Approved
          </span>
        )}
        {isRejected && (
          <span className="ml-auto text-[10px] font-medium text-red-400 bg-red-500/10 px-1.5 py-0.5 rounded">
            Rejected
          </span>
        )}
      </div>

      {/* Feature/Task List */}
      <div className="px-3 py-2 space-y-2">
        {proposal.features.map((feature, fi) => (
          <div key={fi}>
            <div className="text-xs font-medium text-zinc-300 mb-1">
              {feature.name}
            </div>
            <div className="space-y-1 pl-2">
              {feature.tasks.map((task, ti) => (
                <div
                  key={ti}
                  className="flex items-start gap-2 text-[11px] text-zinc-400"
                >
                  <span className="text-zinc-600 mt-0.5">-</span>
                  <span>
                    <span className="text-zinc-300">{task.title}</span>
                    <span className="ml-1 text-zinc-600">
                      ({task.agentType})
                    </span>
                  </span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* Actions */}
      {isPending && (
        <div className="flex items-center gap-2 px-3 py-2 border-t border-zinc-700 bg-zinc-800/30">
          <button
            onClick={() =>
              approveProposal(
                message.id,
                JSON.stringify({ ...proposal, status: "approved" }),
              )
            }
            className="flex items-center gap-1 px-2.5 py-1 text-[11px] font-medium text-green-400 bg-green-500/10 hover:bg-green-500/20 rounded transition-colors"
          >
            <Check className="w-3 h-3" /> Approve
          </button>
          <button
            onClick={() => rejectProposal(message.id)}
            className="flex items-center gap-1 px-2.5 py-1 text-[11px] font-medium text-red-400 bg-red-500/10 hover:bg-red-500/20 rounded transition-colors"
          >
            <X className="w-3 h-3" /> Reject
          </button>
        </div>
      )}
    </div>
  );
}
