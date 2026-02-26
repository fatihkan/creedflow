import { useState } from "react";
import { CreditCard, X } from "lucide-react";
import * as api from "../../tauri";

interface Props {
  onClose: () => void;
}

const PLANS = [
  {
    id: "monthly",
    name: "Monthly",
    price: "$29",
    period: "/month",
    features: [
      "Unlimited projects",
      "All AI backends",
      "Priority support",
      "Advanced analytics",
    ],
  },
  {
    id: "yearly",
    name: "Yearly",
    price: "$249",
    period: "/year",
    badge: "Save 28%",
    features: [
      "Everything in Monthly",
      "2 months free",
      "Early access to features",
      "Custom MCP servers",
    ],
  },
];

export function SubscriptionSheet({ onClose }: Props) {
  const [loading, setLoading] = useState<string | null>(null);

  const handleSubscribe = async (plan: string) => {
    setLoading(plan);
    try {
      await api.openStripeCheckout(plan);
    } catch (e) {
      console.error("Failed to open checkout:", e);
    } finally {
      setLoading(null);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
      <div className="w-full max-w-lg bg-zinc-900 border border-zinc-800 rounded-xl p-6">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-semibold text-zinc-200">
            Upgrade to Pro
          </h2>
          <button
            onClick={onClose}
            className="p-1 text-zinc-500 hover:text-zinc-300 rounded"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="grid grid-cols-2 gap-4">
          {PLANS.map((plan) => (
            <div
              key={plan.id}
              className="border border-zinc-800 rounded-lg p-4 flex flex-col"
            >
              <div className="flex items-center gap-2 mb-2">
                <h3 className="text-sm font-semibold text-zinc-200">
                  {plan.name}
                </h3>
                {plan.badge && (
                  <span className="text-[10px] bg-brand-600/20 text-brand-400 px-1.5 py-0.5 rounded">
                    {plan.badge}
                  </span>
                )}
              </div>
              <div className="mb-3">
                <span className="text-2xl font-bold text-zinc-100">
                  {plan.price}
                </span>
                <span className="text-xs text-zinc-500">{plan.period}</span>
              </div>
              <ul className="space-y-1.5 mb-4 flex-1">
                {plan.features.map((feature) => (
                  <li
                    key={feature}
                    className="text-xs text-zinc-400 flex items-start gap-1.5"
                  >
                    <span className="text-brand-400 mt-0.5">&#10003;</span>
                    {feature}
                  </li>
                ))}
              </ul>
              <button
                onClick={() => handleSubscribe(plan.id)}
                disabled={loading !== null}
                className="flex items-center justify-center gap-1.5 px-4 py-2 text-xs bg-brand-600 text-white rounded-md hover:bg-brand-700 disabled:opacity-50"
              >
                <CreditCard className="w-3.5 h-3.5" />
                {loading === plan.id ? "Opening..." : "Subscribe"}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
