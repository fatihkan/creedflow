import type { AppSettings } from "../../types/models";
import { useTranslation } from "react-i18next";

interface NotificationsStepProps {
  settings: AppSettings;
  onUpdate: (s: AppSettings) => Promise<void>;
}

export function NotificationsStep({ settings, onUpdate }: NotificationsStepProps) {
  const { t } = useTranslation();
  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-zinc-200">{t("setup.notifications")}</h3>
      <p className="text-xs text-zinc-500">
        {t("setup.notificationsDescription")}
      </p>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">
          {t("setup.botToken")}
        </label>
        <input
          type="text"
          value={settings.telegramBotToken ?? ""}
          onChange={(e) =>
            onUpdate({
              ...settings,
              telegramBotToken: e.target.value || null,
            })
          }
          placeholder="123456:ABC..."
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
        />
      </div>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">
          {t("setup.chatId")}
        </label>
        <input
          type="text"
          value={settings.telegramChatId ?? ""}
          onChange={(e) =>
            onUpdate({
              ...settings,
              telegramChatId: e.target.value || null,
            })
          }
          placeholder="-100123456789"
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
        />
      </div>

      <hr className="border-zinc-700" />

      <h4 className="text-sm font-semibold text-zinc-300">Slack</h4>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">
          Slack Webhook URL
        </label>
        <input
          type="text"
          value={settings.slackWebhookUrl ?? ""}
          onChange={(e) =>
            onUpdate({
              ...settings,
              slackWebhookUrl: e.target.value || null,
            })
          }
          placeholder="https://hooks.slack.com/services/T.../B.../..."
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
        />
        <p className="text-[10px] text-zinc-600 mt-1">
          Create a Slack app → Incoming Webhooks → copy URL
        </p>
      </div>
    </div>
  );
}
