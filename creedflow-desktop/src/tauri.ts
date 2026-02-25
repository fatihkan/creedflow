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

// ─── Reviews ─────────────────────────────────────────────────────────────────

export const listReviews = () => invoke<Review[]>("list_reviews");

export const approveReview = (id: string) =>
  invoke<void>("approve_review", { id });

// ─── Agents ──────────────────────────────────────────────────────────────────

export const listAgentTypes = () => invoke<AgentTypeInfo[]>("list_agent_types");

// ─── Assets ──────────────────────────────────────────────────────────────────

export const listAssets = (projectId: string) =>
  invoke<GeneratedAsset[]>("list_assets", { projectId });

// ─── Publishing ──────────────────────────────────────────────────────────────

export const listChannels = () => invoke<PublishingChannel[]>("list_channels");

export const listPublications = () =>
  invoke<Publication[]>("list_publications");
