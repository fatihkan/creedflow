import { useEffect, useState } from "react";
import {
  Radio,
  Plus,
  Trash2,
  Pencil,
  ExternalLink,
  ToggleLeft,
  ToggleRight,
  X,
} from "lucide-react";
import type { PublishingChannel, Publication } from "../../types/models";
import * as api from "../../tauri";
import { useErrorToast } from "../../hooks/useErrorToast";

type ChannelType = "medium" | "wordpress" | "twitter" | "linkedin" | "devTo";

const CHANNEL_TYPES: { value: ChannelType; label: string; color: string }[] = [
  { value: "medium", label: "Medium", color: "bg-green-500/20 text-green-400" },
  { value: "wordpress", label: "WordPress", color: "bg-blue-500/20 text-blue-400" },
  { value: "twitter", label: "Twitter", color: "bg-sky-500/20 text-sky-400" },
  { value: "linkedin", label: "LinkedIn", color: "bg-indigo-500/20 text-indigo-400" },
  { value: "devTo", label: "Dev.to", color: "bg-zinc-500/20 text-zinc-300" },
];

const CREDENTIAL_FIELDS: Record<ChannelType, { key: string; label: string; type: string }[]> = {
  medium: [{ key: "integrationToken", label: "Integration Token", type: "password" }],
  wordpress: [
    { key: "url", label: "Site URL", type: "text" },
    { key: "username", label: "Username", type: "text" },
    { key: "appPassword", label: "Application Password", type: "password" },
  ],
  twitter: [
    { key: "apiKey", label: "API Key", type: "password" },
    { key: "apiSecret", label: "API Secret", type: "password" },
  ],
  linkedin: [{ key: "accessToken", label: "Access Token", type: "password" }],
  devTo: [{ key: "apiKey", label: "API Key", type: "password" }],
};

function getTypeInfo(type: string) {
  return CHANNEL_TYPES.find((t) => t.value === type) ?? CHANNEL_TYPES[0];
}

export function PublishingView() {
  const [tab, setTab] = useState<"channels" | "publications">("channels");
  const [channels, setChannels] = useState<PublishingChannel[]>([]);
  const [publications, setPublications] = useState<Publication[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editingChannel, setEditingChannel] = useState<PublishingChannel | null>(null);
  const withError = useErrorToast();

  const fetchData = async () => {
    setLoading(true);
    await withError(async () => {
      const [ch, pub] = await Promise.all([
        api.listChannels(),
        api.listPublications(),
      ]);
      setChannels(ch);
      setPublications(pub);
    });
    setLoading(false);
  };

  useEffect(() => {
    fetchData();
  }, []);

  const handleToggle = async (channel: PublishingChannel) => {
    await withError(async () => {
      const updated = await api.updateChannel(
        channel.id,
        channel.name,
        channel.channelType,
        channel.credentialsJson,
        channel.defaultTags,
        !channel.isEnabled,
      );
      setChannels((prev) => prev.map((c) => (c.id === updated.id ? updated : c)));
    });
  };

  const handleDelete = async (id: string) => {
    await withError(async () => {
      await api.deleteChannel(id);
      setChannels((prev) => prev.filter((c) => c.id !== id));
    });
  };

  const handleEdit = (channel: PublishingChannel) => {
    setEditingChannel(channel);
    setShowForm(true);
  };

  const handleSaved = (channel: PublishingChannel) => {
    setChannels((prev) => {
      const exists = prev.find((c) => c.id === channel.id);
      if (exists) return prev.map((c) => (c.id === channel.id ? channel : c));
      return [...prev, channel];
    });
    setShowForm(false);
    setEditingChannel(null);
  };

  const getChannelName = (id: string) =>
    channels.find((c) => c.id === id)?.name ?? "Unknown";

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <div className="flex items-center gap-2">
          <Radio className="w-4 h-4 text-zinc-400" />
          <h2 className="text-sm font-medium text-zinc-200">Publishing</h2>
        </div>
        {tab === "channels" && (
          <button
            onClick={() => {
              setEditingChannel(null);
              setShowForm(true);
            }}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded transition-colors"
          >
            <Plus className="w-3.5 h-3.5" />
            Add Channel
          </button>
        )}
      </div>

      {/* Tabs */}
      <div className="flex border-b border-zinc-800">
        {(["channels", "publications"] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2 text-xs font-medium capitalize transition-colors ${
              tab === t
                ? "text-brand-400 border-b-2 border-brand-400"
                : "text-zinc-500 hover:text-zinc-300"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex-1 flex items-center justify-center text-zinc-500 text-sm">
          Loading...
        </div>
      ) : tab === "channels" ? (
        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          {channels.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-32 text-zinc-500">
              <Radio className="w-8 h-8 mb-2 opacity-40" />
              <p className="text-sm">No publishing channels configured</p>
              <p className="text-xs mt-1 text-zinc-600">
                Add a channel to publish content to external platforms
              </p>
            </div>
          ) : (
            channels.map((channel) => {
              const info = getTypeInfo(channel.channelType);
              return (
                <div
                  key={channel.id}
                  className="flex items-center gap-3 px-4 py-3 bg-zinc-900/40 border border-zinc-800 rounded-lg"
                >
                  <span className={`text-[10px] font-medium px-2 py-0.5 rounded-full ${info.color}`}>
                    {info.label}
                  </span>
                  <span className="text-sm text-zinc-200 flex-1 truncate">
                    {channel.name}
                  </span>
                  {channel.defaultTags && (
                    <span className="text-[10px] text-zinc-500 truncate max-w-[120px]">
                      {channel.defaultTags}
                    </span>
                  )}
                  <button
                    onClick={() => handleToggle(channel)}
                    className="text-zinc-400 hover:text-zinc-200 transition-colors"
                    title={channel.isEnabled ? "Disable" : "Enable"}
                  >
                    {channel.isEnabled ? (
                      <ToggleRight className="w-5 h-5 text-green-400" />
                    ) : (
                      <ToggleLeft className="w-5 h-5 text-zinc-500" />
                    )}
                  </button>
                  <button
                    onClick={() => handleEdit(channel)}
                    className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-zinc-200 transition-colors"
                  >
                    <Pencil className="w-3.5 h-3.5" />
                  </button>
                  <button
                    onClick={() => handleDelete(channel.id)}
                    className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-red-400 transition-colors"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              );
            })
          )}
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          {publications.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-32 text-zinc-500">
              <p className="text-sm">No publications yet</p>
              <p className="text-xs mt-1 text-zinc-600">
                Publications appear when content is published through channels
              </p>
            </div>
          ) : (
            publications.map((pub) => {
              const statusColor = {
                published: "bg-green-500/20 text-green-400",
                publishing: "bg-blue-500/20 text-blue-400",
                scheduled: "bg-amber-500/20 text-amber-400",
                failed: "bg-red-500/20 text-red-400",
              }[pub.status] ?? "bg-zinc-500/20 text-zinc-400";
              return (
                <div
                  key={pub.id}
                  className="flex items-center gap-3 px-4 py-3 bg-zinc-900/40 border border-zinc-800 rounded-lg"
                >
                  <span className={`text-[10px] font-medium px-2 py-0.5 rounded-full ${statusColor}`}>
                    {pub.status}
                  </span>
                  <span className="text-xs text-zinc-400 flex-1">
                    {getChannelName(pub.channelId)}
                  </span>
                  <span className="text-[10px] text-zinc-500">
                    {new Date(pub.createdAt).toLocaleDateString()}
                  </span>
                  {pub.publishedUrl && (
                    <a
                      href={pub.publishedUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-brand-400 transition-colors"
                    >
                      <ExternalLink className="w-3.5 h-3.5" />
                    </a>
                  )}
                </div>
              );
            })
          )}
        </div>
      )}

      {/* Channel form modal */}
      {showForm && (
        <ChannelFormModal
          channel={editingChannel}
          onClose={() => {
            setShowForm(false);
            setEditingChannel(null);
          }}
          onSaved={handleSaved}
        />
      )}
    </div>
  );
}

function ChannelFormModal({
  channel,
  onClose,
  onSaved,
}: {
  channel: PublishingChannel | null;
  onClose: () => void;
  onSaved: (channel: PublishingChannel) => void;
}) {
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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" role="dialog" aria-modal="true">
      <div className="bg-zinc-900 border border-zinc-700 rounded-xl w-[440px] p-5 shadow-2xl">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-sm font-semibold text-zinc-200">
            {isEditing ? "Edit Channel" : "Add Publishing Channel"}
          </h3>
          <button onClick={onClose} className="text-zinc-500 hover:text-zinc-300">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="space-y-3">
          <input
            type="text"
            placeholder="Channel name"
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
                Credentials
              </p>
              {fields.map((f) => (
                <div key={f.key}>
                  <label className="text-[11px] text-zinc-400 mb-1 block">{f.label}</label>
                  <input
                    type={f.type}
                    value={credentials[f.key] ?? ""}
                    onChange={(e) =>
                      setCredentials((prev) => ({ ...prev, [f.key]: e.target.value }))
                    }
                    placeholder={f.label}
                    className="w-full px-3 py-1.5 text-sm bg-zinc-800 border border-zinc-700 rounded-md text-zinc-200 placeholder:text-zinc-600 focus:outline-none focus:border-brand-500 font-mono"
                  />
                </div>
              ))}
            </div>
          )}

          <input
            type="text"
            placeholder="Default tags (comma-separated)"
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
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={!name.trim() || saving}
            className="px-3 py-1.5 text-xs bg-brand-600 hover:bg-brand-500 text-white rounded disabled:opacity-50 transition-colors"
          >
            {saving ? "Saving..." : isEditing ? "Update" : "Create"}
          </button>
        </div>
      </div>
    </div>
  );
}
