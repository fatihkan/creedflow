import { useSettingsStore } from "../../store/settingsStore";

export function TelegramSettings() {
  const { settings, updateSettings } = useSettingsStore();
  if (!settings) return null;

  return (
    <div className="space-y-4">
      <p className="text-xs text-zinc-500">
        Configure Telegram notifications for task milestones, deploy events, and failures.
      </p>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">Bot Token</label>
        <input
          type="password"
          value={settings.telegramBotToken ?? ""}
          onChange={(e) =>
            updateSettings({ ...settings, telegramBotToken: e.target.value || null })
          }
          placeholder="123456:ABC-DEF..."
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
        />
      </div>
      <div>
        <label className="block text-xs text-zinc-400 mb-1">Default Chat ID</label>
        <input
          type="text"
          value={settings.telegramChatId ?? ""}
          onChange={(e) =>
            updateSettings({ ...settings, telegramChatId: e.target.value || null })
          }
          placeholder="-100123456789"
          className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300 placeholder:text-zinc-600"
        />
      </div>
      <p className="text-[10px] text-zinc-600">
        Create a bot via @BotFather on Telegram. The chat ID is the group or channel where notifications will be sent.
      </p>
    </div>
  );
}
