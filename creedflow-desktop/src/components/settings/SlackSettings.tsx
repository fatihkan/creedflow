import { useSettingsStore } from "../../store/settingsStore";

export function SlackSettings() {
  const { settings, updateSettings } = useSettingsStore();
  if (!settings) return null;

  return (
    <div className="space-y-4">
      <p className="text-xs text-zinc-500">
        Configure Slack notifications via Incoming Webhooks for task milestones, deploy events, and failures.
      </p>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">Webhook URL</label>
        <input
          type="password"
          value={settings.slackWebhookUrl ?? ""}
          onChange={(e) =>
            updateSettings({ ...settings, slackWebhookUrl: e.target.value || null })
          }
          placeholder="https://hooks.slack.com/services/T.../B.../..."
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
        />
      </div>
      <p className="text-[10px] text-zinc-600">
        Create a Slack app → Incoming Webhooks → copy the webhook URL. Notifications are sent to the channel linked to the webhook.
      </p>
    </div>
  );
}
