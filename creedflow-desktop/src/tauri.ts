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
) =>
  invoke<Project>("create_project", {
    name,
    description,
    techStack,
    projectType,
  });

export const updateProject = (project: Project) =>
  invoke<Project>("update_project", { project });

export const deleteProject = (id: string) =>
  invoke<void>("delete_project", { id });

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

export const openStripeCheckout = (plan: string) =>
  invoke<void>("open_stripe_checkout", { plan });

// ─── Costs ───────────────────────────────────────────────────────────────────

export const getCostSummary = () => invoke<CostSummary>("get_cost_summary");

export const getCostsByProject = (projectId: string) =>
  invoke<CostTracking[]>("get_costs_by_project", { projectId });

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

// ─── Publishing ──────────────────────────────────────────────────────────────

export const listChannels = () => invoke<PublishingChannel[]>("list_channels");

export const listPublications = () =>
  invoke<Publication[]>("list_publications");

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

// ─── Dependencies ────────────────────────────────────────────────────────────

export const detectDependencies = () =>
  invoke<DependencyStatus[]>("detect_dependencies");

export const installDependency = (name: string) =>
  invoke<string>("install_dependency", { name });
