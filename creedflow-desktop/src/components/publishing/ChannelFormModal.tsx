import { useState } from "react";
import { X } from "lucide-react";
import type { PublishingChannel } from "../../types/models";
import * as api from "../../tauri";
import { useErrorToast } from "../../hooks/useErrorToast";
import { FocusTrap } from "../shared/FocusTrap";
import { useTranslation } from "react-i18next";

type ChannelType = "medium" | "wordpress" | "twitter" | "linkedin" | "devTo";

const CHANNEL_TYPES: { value: ChannelType; label: string }[] = [
  { value: "medium", label: "Medium" },
  { value: "wordpress", label: "WordPress" },
  { value: "twitter", label: "Twitter" },
  { value: "linkedin", label: "LinkedIn" },
  { value: "devTo", label: "Dev.to" },
];

const CREDENTIAL_FIELDS: Record<ChannelType, { key: string; labelKey: string; type: string }[]> = {
  medium: [{ key: "integrationToken", labelKey: "publishing.credentials.integrationToken", type: "password" }],
  wordpress: [
    { key: "url", labelKey: "publishing.credentials.siteUrl", type: "text" },
    { key: "username", labelKey: "publishing.credentials.username", type: "text" },
    { key: "appPassword", labelKey: "publishing.credentials.applicationPassword", type: "password" },
  ],
  twitter: [
    { key: "apiKey", labelKey: "publishing.credentials.apiKey", type: "password" },
    { key: "apiSecret", labelKey: "publishing.credentials.apiSecret", type: "password" },
  ],
  linkedin: [{ key: "accessToken", labelKey: "publishing.credentials.accessToken", type: "password" }],
  devTo: [{ key: "apiKey", labelKey: "publishing.credentials.apiKey", type: "password" }],
};

interface ChannelFormModalProps {
  channel: PublishingChannel | null;
  onClose: () => void;
  onSaved: (channel: PublishingChannel) => void;
}

export function ChannelFormModal({ channel, onClose, onSaved }: ChannelFormModalProps) {
  const { t } = useTranslation();
  const isEditing = channel !== null;
  const [name, setName] = useState(channel?.name ?? "");
  const [channelType, setChannelType] = useState<ChannelType>(
    (channel?.channelType as ChannelType) ?? "medium",
  );
  const [credentials, setCredentials] = useState<Record<string, string>>(() => {
    if (channel?.credentialsJson) {
      try {
        return JSON.parse(channel.credentialsJson);
      } catch {
        return {};
      }
    }
    return {};
  });
  const [defaultTags, setDefaultTags] = useState(channel?.defaultTags ?? "");
  const [saving, setSaving] = useState(false);
  const withError = useErrorToast();

  const fields = CREDENTIAL_FIELDS[channelType] ?? [];

  const handleSave = async () => {
    setSaving(true);
    await withError(async () => {
      const credJson = JSON.stringify(credentials);
      let result: PublishingChannel;
      if (isEditing) {
        result = await api.updateChannel(
          channel.id,
          name,
          channelType,
          credJson,
          defaultTags,
          channel.isEnabled,
        );
      } else {
        result = await api.createChannel(name, channelType, credJson, defaultTags);
      }
      onSaved(result);
    });
    setSaving(false);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" role="dialog" aria-modal="true" aria-labelledby="channel-form-title">
      <FocusTrap>
      <div className="bg-zinc-900 border border-zinc-700 rounded-xl w-[440px] p-5 shadow-2xl">
        <div className="flex items-center justify-between mb-4">
          <h3 id="channel-form-title" className="text-sm font-semibold text-zinc-200">
            {isEditing ? t("publishing.channelForm.editTitle") : t("publishing.channelForm.addTitle")}
          </h3>
          <button onClick={onClose} className="text-zinc-500 hover:text-zinc-300" aria-label="Close dialog">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="space-y-3">
          <input
            type="text"
            placeholder={t("publishing.channelForm.namePlaceholder")}
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:border-brand-500"
          />

          <select
            value={channelType}
            onChange={(e) => {
              setChannelType(e.target.value as ChannelType);
              setCredentials({});
            }}
            className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-300 focus:outline-none focus:border-brand-500"
          >
            {CHANNEL_TYPES.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </select>

          {/* Dynamic credential fields */}
          {fields.length > 0 && (
            <div className="space-y-2">
              <p className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">
                {t("publishing.channelForm.credentials")}
              </p>
              {fields.map((f) => (
                <div key={f.key}>
                  <label className="text-[11px] text-zinc-400 mb-1 block">{t(f.labelKey)}</label>
                  <input
                    type={f.type}
                    value={credentials[f.key] ?? ""}
                    onChange={(e) =>
                      setCredentials((prev) => ({ ...prev, [f.key]: e.target.value }))
                    }
                    placeholder={t(f.labelKey)}
                    className="w-full px-3 py-1.5 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-600 focus:outline-none focus:border-brand-500 font-mono"
                  />
                </div>
              ))}
            </div>
          )}

          <input
            type="text"
            placeholder={t("publishing.channelForm.tagsPlaceholder")}
            value={defaultTags}
            onChange={(e) => setDefaultTags(e.target.value)}
            className="w-full px-3 py-2 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:border-brand-500"
          />
        </div>

        <div className="flex justify-end gap-2 mt-4">
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-xs text-zinc-400 hover:text-zinc-200 transition-colors"
          >
            {t("publishing.channelForm.cancel")}
          </button>
          <button
            onClick={handleSave}
            disabled={!name.trim() || saving}
            className="px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded disabled:opacity-50 transition-colors"
          >
            {saving ? t("publishing.channelForm.saving") : isEditing ? t("publishing.channelForm.update") : t("publishing.channelForm.create")}
          </button>
        </div>
      </div>
      </FocusTrap>
    </div>
  );
}
