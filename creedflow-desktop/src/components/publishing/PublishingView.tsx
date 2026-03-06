import { useEffect, useState } from "react";
import {
  Radio,
  Plus,
  Trash2,
  Pencil,
  ExternalLink,
  ToggleLeft,
  ToggleRight,
} from "lucide-react";
import type { PublishingChannel, Publication } from "../../types/models";
import * as api from "../../tauri";
import { useErrorToast } from "../../hooks/useErrorToast";
import { ChannelFormModal } from "./ChannelFormModal";
import { useTranslation } from "react-i18next";

const CHANNEL_TYPE_COLORS: Record<string, string> = {
  medium: "bg-green-500/20 text-green-400",
  wordpress: "bg-blue-500/20 text-blue-400",
  twitter: "bg-sky-500/20 text-sky-400",
  linkedin: "bg-indigo-500/20 text-indigo-400",
  devTo: "bg-zinc-500/20 text-zinc-300",
};

const CHANNEL_TYPE_LABELS: Record<string, string> = {
  medium: "Medium",
  wordpress: "WordPress",
  twitter: "Twitter",
  linkedin: "LinkedIn",
  devTo: "Dev.to",
};

function getTypeInfo(type: string) {
  return {
    color: CHANNEL_TYPE_COLORS[type] ?? "bg-zinc-500/20 text-zinc-300",
    label: CHANNEL_TYPE_LABELS[type] ?? type,
  };
}

export function PublishingView() {
  const { t } = useTranslation();
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
          <h2 className="text-sm font-medium text-zinc-200">{t("publishing.title")}</h2>
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
            {t("publishing.addChannel")}
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
          {t("publishing.loading")}
        </div>
      ) : tab === "channels" ? (
        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          {channels.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-32 text-zinc-500">
              <Radio className="w-8 h-8 mb-2 opacity-40" />
              <p className="text-sm">{t("publishing.noChannels")}</p>
              <p className="text-xs mt-1 text-zinc-600">
                {t("publishing.noChannelsDescription")}
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
                    title={channel.isEnabled ? t("publishing.disable") : t("publishing.enable")}
                    aria-label={channel.isEnabled ? `Disable ${channel.name}` : `Enable ${channel.name}`}
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
                    aria-label={`Edit ${channel.name}`}
                  >
                    <Pencil className="w-3.5 h-3.5" />
                  </button>
                  <button
                    onClick={() => handleDelete(channel.id)}
                    className="p-1 rounded hover:bg-zinc-700 text-zinc-500 hover:text-red-400 transition-colors"
                    aria-label={`Delete ${channel.name}`}
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
              <p className="text-sm">{t("publishing.noPublications")}</p>
              <p className="text-xs mt-1 text-zinc-600">
                {t("publishing.noPublicationsDescription")}
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

