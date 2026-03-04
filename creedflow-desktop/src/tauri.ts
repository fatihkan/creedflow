import { invoke } from "@tauri-apps/api/core";
import type {
  Project,
  AgentTask,
  BackendInfo,
  AppSettings,
  CostSummary,
  CostTracking,
  Review,
  AgentTypeInfo,
  GeneratedAsset,
  PublishingChannel,
  Publication,
  DeploymentInfo,
  DependencyStatus,
  PackageManagerInfo,
  DetectedEditor,
  PromptChainWithSteps,
  PromptChain,
  PromptChainStep,
  PromptEffectivenessStats,
  ProjectMessage,
  Prompt,
  PromptVersion,
  ProjectTimeStats,
  ProjectTemplate,
  TaskComment,
  PromptUsageRecord,
} from "./types/models";

// ─── Projects ────────────────────────────────────────────────────────────────

export const listProjects = () => invoke<Project[]>("list_projects");

export const getProject = (id: string) =>
  invoke<Project>("get_project", { id });

export const createProject = (
  name: string,
  description: string,
  techStack: string,
  projectType: string,
  directoryPath?: string,
) =>
  invoke<Project>("create_project", {
    name,
    description,
    techStack,
    projectType,
    directoryPath: directoryPath ?? null,
  });

export const updateProject = (project: Project) =>
  invoke<Project>("update_project", { project });

export const deleteProject = (id: string) =>
  invoke<void>("delete_project", { id });

export const exportProjectDocs = (id: string, outputPath: string) =>
  invoke<string>("export_project_docs", { id, outputPath });

export const getProjectTimeStats = (projectId: string) =>
  invoke<ProjectTimeStats>("get_project_time_stats", { projectId });

export const exportProjectZip = (projectId: string, outputPath: string) =>
  invoke<string>("export_project_zip", { projectId, outputPath });

export const listProjectTemplates = () =>
  invoke<ProjectTemplate[]>("list_project_templates");

export const createProjectFromTemplate = (templateId: string, name: string, directoryPath?: string) =>
  invoke<Project>("create_project_from_template", {
    templateId,
    name,
    directoryPath: directoryPath ?? null,
  });

// ─── Tasks ───────────────────────────────────────────────────────────────────

export const listTasks = (projectId: string) =>
  invoke<AgentTask[]>("list_tasks", { projectId });

export const getTask = (id: string) => invoke<AgentTask>("get_task", { id });

export const createTask = (
  projectId: string,
  title: string,
  description: string,
  agentType: string,
  priority?: number,
) =>
  invoke<AgentTask>("create_task", {
    projectId,
    title,
    description,
    agentType,
    priority,
  });

export const updateTaskStatus = (id: string, status: string) =>
  invoke<void>("update_task_status", { id, status });

export const archiveTasks = (ids: string[]) =>
  invoke<void>("archive_tasks", { ids });

export const restoreTasks = (ids: string[]) =>
  invoke<void>("restore_tasks", { ids });

export const permanentlyDeleteTasks = (ids: string[]) =>
  invoke<void>("permanently_delete_tasks", { ids });

export const listArchivedTasks = (projectId?: string) =>
  invoke<AgentTask[]>("list_archived_tasks", { projectId: projectId ?? null });

export const retryTaskWithRevision = (id: string, revisionPrompt?: string) =>
  invoke<void>("retry_task_with_revision", {
    id,
    revisionPrompt: revisionPrompt ?? null,
  });

export const batchRetryTasks = (ids: string[]) =>
  invoke<void>("batch_retry_tasks", { ids });

export const batchCancelTasks = (ids: string[]) =>
  invoke<void>("batch_cancel_tasks", { ids });

export const duplicateTask = (id: string) =>
  invoke<AgentTask>("duplicate_task", { id });

export const addTaskComment = (taskId: string, content: string, author?: string) =>
  invoke<TaskComment>("add_task_comment", { taskId, content, author: author ?? null });

export const listTaskComments = (taskId: string) =>
  invoke<TaskComment[]>("list_task_comments", { taskId });

export const getTaskPromptHistory = (taskId: string) =>
  invoke<PromptUsageRecord[]>("get_task_prompt_history", { taskId });

// ─── Backends ────────────────────────────────────────────────────────────────

export const listBackends = () => invoke<BackendInfo[]>("list_backends");

export const checkBackend = (backendType: string) =>
  invoke<BackendInfo>("check_backend", { backendType });

export const toggleBackend = (backendType: string, enabled: boolean) =>
  invoke<void>("toggle_backend", { backendType, enabled });

// ─── Settings ────────────────────────────────────────────────────────────────

export const getSettings = () => invoke<AppSettings>("get_settings");

export const updateSettings = (settings: AppSettings) =>
  invoke<void>("update_settings", { settings });

// ─── Costs ───────────────────────────────────────────────────────────────────

export const getCostSummary = () => invoke<CostSummary>("get_cost_summary");

export const getCostsByProject = (projectId: string) =>
  invoke<CostTracking[]>("get_costs_by_project", { projectId });

export interface CostBreakdown {
  label: string;
  cost: number;
  tasks: number;
  tokens: number;
}

export const getCostByAgent = () =>
  invoke<CostBreakdown[]>("get_cost_by_agent");

export const getCostByBackend = () =>
  invoke<CostBreakdown[]>("get_cost_by_backend");

export const getCostTimeline = () =>
  invoke<CostBreakdown[]>("get_cost_timeline");

export const getTaskStatistics = () =>
  invoke<import("./types/models").TaskStatistics>("get_task_statistics");

// ─── Reviews ─────────────────────────────────────────────────────────────────

export const listReviews = () => invoke<Review[]>("list_reviews");

export const approveReview = (id: string) =>
  invoke<void>("approve_review", { id });

export const rejectReview = (id: string) =>
  invoke<void>("reject_review", { id });

export const listReviewsForTask = (taskId: string) =>
  invoke<Review[]>("list_reviews_for_task", { taskId });

export const getPendingReviewCount = () =>
  invoke<number>("get_pending_review_count");

// ─── Agents ──────────────────────────────────────────────────────────────────

export const listAgentTypes = () => invoke<AgentTypeInfo[]>("list_agent_types");

export const getAgentBackendInfo = () =>
  invoke<
    { agentType: string; defaultPreference: string; allowedBackends: string[] }[]
  >("get_agent_backend_info");

// ─── Assets ──────────────────────────────────────────────────────────────────

export const listAssets = (projectId: string) =>
  invoke<GeneratedAsset[]>("list_assets", { projectId });

export const getAsset = (id: string) =>
  invoke<GeneratedAsset>("get_asset", { id });

export const getAssetVersions = (assetId: string) =>
  invoke<GeneratedAsset[]>("get_asset_versions", { assetId });

export const approveAsset = (id: string, approved: boolean) =>
  invoke<void>("approve_asset", { id, approved });

export const deleteAsset = (id: string) =>
  invoke<void>("delete_asset", { id });

// ─── Publishing ──────────────────────────────────────────────────────────────

export const listChannels = () => invoke<PublishingChannel[]>("list_channels");

export const listPublications = () =>
  invoke<Publication[]>("list_publications");

export const createChannel = (
  name: string,
  channelType: string,
  credentialsJson: string,
  defaultTags: string,
) =>
  invoke<PublishingChannel>("create_channel", {
    name,
    channelType,
    credentialsJson,
    defaultTags,
  });

export const updateChannel = (
  id: string,
  name: string,
  channelType: string,
  credentialsJson: string,
  defaultTags: string,
  isEnabled: boolean,
) =>
  invoke<PublishingChannel>("update_channel", {
    id,
    name,
    channelType,
    credentialsJson,
    defaultTags,
    isEnabled,
  });

export const deleteChannel = (id: string) =>
  invoke<void>("delete_channel", { id });

// ─── Deploy ──────────────────────────────────────────────────────────────────

export const listDeployments = (projectId: string) =>
  invoke<DeploymentInfo[]>("list_deployments", { projectId });

export const createDeployment = (
  projectId: string,
  environment: string,
  version: string,
  deployMethod: string,
) =>
  invoke<DeploymentInfo>("create_deployment", {
    projectId,
    environment,
    version,
    deployMethod,
  });

export const deleteDeployments = (ids: string[]) =>
  invoke<void>("delete_deployments", { ids });

export const cancelDeployment = (id: string) =>
  invoke<void>("cancel_deployment", { id });

export const getDeploymentLogs = (id: string) =>
  invoke<string | null>("get_deployment_logs", { id });

// ─── Dependencies ────────────────────────────────────────────────────────────

export const detectDependencies = () =>
  invoke<DependencyStatus[]>("detect_dependencies");

export const installDependency = (name: string) =>
  invoke<string>("install_dependency", { name });

export const detectPackageManager = () =>
  invoke<PackageManagerInfo>("detect_package_manager_cmd");

// ─── Platform ────────────────────────────────────────────────────────────────

export const openTerminal = (path: string) =>
  invoke<void>("open_terminal", { path });

export const openInFileManager = (path: string) =>
  invoke<void>("open_in_file_manager", { path });

export const openUrl = (url: string) =>
  invoke<void>("open_url", { url });

export const detectEditors = () =>
  invoke<DetectedEditor[]>("detect_editors");

export const openInEditor = (path: string, editorCommand: string) =>
  invoke<void>("open_in_editor", { path, editorCommand });

export const getPreferredEditor = () =>
  invoke<string | null>("get_preferred_editor");

export const setPreferredEditor = (editorCommand: string | null) =>
  invoke<void>("set_preferred_editor", { editorCommand });

export const getPlatform = () => invoke<string>("get_platform");

// ─── Git ────────────────────────────────────────────────────────────────────

export interface GitLogEntry {
  hash: string;
  shortHash: string;
  parents: string[];
  decorations: string;
  author: string;
  timestamp: number;
  message: string;
}

// ─── Prompt Chains ───────────────────────────────────────────────────────────

export const listPromptChains = () =>
  invoke<PromptChainWithSteps[]>("list_prompt_chains");

export const getPromptChain = (id: string) =>
  invoke<PromptChainWithSteps>("get_prompt_chain", { id });

export const createPromptChain = (name: string, description: string, category: string) =>
  invoke<PromptChain>("create_prompt_chain", { name, description, category });

export const deletePromptChain = (id: string) =>
  invoke<void>("delete_prompt_chain", { id });

export const addChainStep = (chainId: string, promptId: string, stepOrder: number, transitionNote?: string) =>
  invoke<PromptChainStep>("add_chain_step", { chainId, promptId, stepOrder, transitionNote: transitionNote ?? null });

export const removeChainStep = (id: string) =>
  invoke<void>("remove_chain_step", { id });

export const reorderChainSteps = (steps: [string, number][]) =>
  invoke<void>("reorder_chain_steps", { steps });

export const updateChainStep = (id: string, transitionNote: string | null) =>
  invoke<void>("update_chain_step", { id, transitionNote });

export const updatePromptChain = (
  id: string,
  name: string,
  description: string,
  category: string,
) =>
  invoke<PromptChain>("update_prompt_chain", { id, name, description, category });

// ─── Prompt Effectiveness ────────────────────────────────────────────────────

export const getPromptEffectiveness = () =>
  invoke<PromptEffectivenessStats[]>("get_prompt_effectiveness");

// ─── Git ────────────────────────────────────────────────────────────────────

export const gitEnsureBranchStructure = (projectId: string) =>
  invoke<void>("git_ensure_branch_structure", { projectId });

export const gitSetupFeatureBranch = (
  projectId: string,
  taskId: string,
  title: string,
) => invoke<string>("git_setup_feature_branch", { projectId, taskId, title });

export const gitAutoCommit = (
  projectId: string,
  taskId: string,
  title: string,
  agentType: string,
) =>
  invoke<string | null>("git_auto_commit", {
    projectId,
    taskId,
    title,
    agentType,
  });

export const gitMergeFeatureToDev = (
  projectId: string,
  branchName: string,
) => invoke<void>("git_merge_feature_to_dev", { projectId, branchName });

export const gitPromoteDevToStaging = (projectId: string) =>
  invoke<string>("git_promote_dev_to_staging", { projectId });

export const gitPromoteStagingToMain = (projectId: string) =>
  invoke<string>("git_promote_staging_to_main", { projectId });

export const gitCurrentBranch = (projectId: string) =>
  invoke<string>("git_current_branch", { projectId });

export const gitLog = (projectId: string, count?: number) =>
  invoke<GitLogEntry[]>("git_log", { projectId, count: count ?? null });

// ─── Git Config ─────────────────────────────────────────────────────────────

export interface GitConfig {
  userName: string;
  userEmail: string;
  gitInstalled: boolean;
  gitVersion: string;
  ghInstalled: boolean;
  ghVersion: string;
}

export const getGitConfig = () => invoke<GitConfig>("get_git_config");

export const setGitConfig = (name: string, email: string) =>
  invoke<void>("set_git_config", { name, email });

// ─── Chat ───────────────────────────────────────────────────────────────────

import type { ChatAttachment } from "./types/models";

export const sendChatMessage = (
  projectId: string,
  content: string,
  role: string,
  attachments?: ChatAttachment[],
) =>
  invoke<ProjectMessage>("send_chat_message", {
    projectId,
    content,
    role,
    attachments: attachments ?? null,
  });

export const streamChatResponse = (
  projectId: string,
  content: string,
  attachments: ChatAttachment[],
) =>
  invoke<string>("stream_chat_response", {
    projectId,
    content,
    attachments,
  });

export const listChatMessages = (projectId: string) =>
  invoke<ProjectMessage[]>("list_chat_messages", { projectId });

export const approveChatProposal = (messageId: string, metadata: string) =>
  invoke<void>("approve_chat_proposal", { messageId, metadata });

export const rejectChatProposal = (messageId: string) =>
  invoke<void>("reject_chat_proposal", { messageId });

// ─── Notifications & Health ──────────────────────────────────────────────────

export const listNotifications = (limit?: number) =>
  invoke<AppNotif[]>("list_notifications", { limit: limit ?? null });

export const getUnreadCount = () =>
  invoke<number>("get_unread_count");

export const markNotificationRead = (id: string) =>
  invoke<void>("mark_notification_read", { id });

export const markAllNotificationsRead = () =>
  invoke<void>("mark_all_notifications_read");

export const dismissNotification = (id: string) =>
  invoke<void>("dismiss_notification", { id });

export const getBackendHealthStatus = () =>
  invoke<HealthEvent[]>("get_backend_health_status");

export const getMcpHealthStatus = () =>
  invoke<HealthEvent[]>("get_mcp_health_status");

// ─── MCP Server Config ─────────────────────────────────────────────────────

import type { MCPServerConfig } from "./types/models";

export const listMcpServers = () =>
  invoke<MCPServerConfig[]>("list_mcp_servers");

export const createMcpServer = (
  name: string,
  command: string,
  arguments_: string,
  environmentVars: string,
) =>
  invoke<MCPServerConfig>("create_mcp_server", {
    name,
    command,
    arguments: arguments_,
    environmentVars,
  });

export const updateMcpServer = (
  id: string,
  name: string,
  command: string,
  arguments_: string,
  environmentVars: string,
  isEnabled: boolean,
) =>
  invoke<MCPServerConfig>("update_mcp_server", {
    id,
    name,
    command,
    arguments: arguments_,
    environmentVars,
    isEnabled,
  });

export const deleteMcpServer = (id: string) =>
  invoke<void>("delete_mcp_server", { id });

// ─── Prompt Import/Export ───────────────────────────────────────────────────

export const exportPrompts = (promptIds: string[], filePath: string) =>
  invoke<string>("export_prompts", { promptIds, filePath });

export const importPrompts = (filePath: string) =>
  invoke<Prompt[]>("import_prompts", { filePath });

// ─── Prompt Versions & Diff ─────────────────────────────────────────────────

import type { PromptVersionDiff, PromptRecommendation, AppNotification as AppNotif, HealthEvent } from "./types/models";

export const getPromptVersions = (promptId: string) =>
  invoke<PromptVersion[]>("get_prompt_versions", { promptId });

export const getPromptVersionDiff = (
  promptId: string,
  versionA: number,
  versionB: number,
) =>
  invoke<PromptVersionDiff>("get_prompt_version_diff", {
    promptId,
    versionA,
    versionB,
  });

// ─── Prompt Recommender ─────────────────────────────────────────────────────

// ─── Updates ────────────────────────────────────────────────────────────────

export interface UpdateInfo {
  latestVersion: string;
  currentVersion: string;
  releaseUrl: string;
  releaseNotes: string;
}

export const checkForUpdates = () =>
  invoke<UpdateInfo | null>("check_for_updates");

// ─── Prompt Recommender ─────────────────────────────────────────────────────

export const getPromptRecommendations = (
  agentType?: string,
  category?: string,
  limit?: number,
) =>
  invoke<PromptRecommendation[]>("get_prompt_recommendations", {
    agentType: agentType ?? null,
    category: category ?? null,
    limit: limit ?? null,
  });
