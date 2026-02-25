// TypeScript interfaces matching Rust model structs

export interface Project {
  id: string;
  name: string;
  description: string;
  techStack: string;
  status: ProjectStatus;
  directoryPath: string;
  projectType: ProjectType;
  telegramChatId: number | null;
  createdAt: string;
  updatedAt: string;
}

export type ProjectStatus =
  | "planning"
  | "analyzing"
  | "in_progress"
  | "reviewing"
  | "deploying"
  | "completed"
  | "failed"
  | "paused";

export type ProjectType = "software" | "content" | "image" | "video" | "general";

export interface AgentTask {
  id: string;
  projectId: string;
  featureId: string | null;
  agentType: AgentType;
  title: string;
  description: string;
  priority: number;
  status: TaskStatus;
  result: string | null;
  errorMessage: string | null;
  retryCount: number;
  maxRetries: number;
  sessionId: string | null;
  branchName: string | null;
  prNumber: number | null;
  costUsd: number | null;
  durationMs: number | null;
  createdAt: string;
  updatedAt: string;
  startedAt: string | null;
  completedAt: string | null;
  backend: string | null;
  promptChainId: string | null;
}

export type AgentType =
  | "analyzer"
  | "coder"
  | "reviewer"
  | "tester"
  | "devops"
  | "monitor"
  | "contentWriter"
  | "designer"
  | "imageGenerator"
  | "videoEditor"
  | "publisher";

export type TaskStatus =
  | "queued"
  | "in_progress"
  | "passed"
  | "failed"
  | "needs_revision"
  | "cancelled";

export interface Review {
  id: string;
  taskId: string;
  score: number;
  verdict: "pass" | "needsRevision" | "fail";
  summary: string;
  issues: string | null;
  suggestions: string | null;
  securityNotes: string | null;
  sessionId: string | null;
  costUsd: number | null;
  isApproved: boolean;
  createdAt: string;
}

export interface CostTracking {
  id: string;
  projectId: string;
  taskId: string | null;
  agentType: AgentType;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  model: string;
  sessionId: string | null;
  backend: string | null;
  createdAt: string;
}

export interface CostSummary {
  totalCost: number;
  totalTasks: number;
  totalTokens: number;
}

export interface BackendInfo {
  backendType: string;
  displayName: string;
  isAvailable: boolean;
  isEnabled: boolean;
  cliPath: string | null;
  color: string;
  isLocal: boolean;
}

export interface AgentTypeInfo {
  agentType: AgentType;
  displayName: string;
  timeoutSeconds: number;
  backendPreference: string;
  hasMcp: boolean;
}

export interface AppSettings {
  projectsDir: string;
  maxConcurrency: number;
  monthlyBudgetUsd: number;
  claudeEnabled: boolean;
  codexEnabled: boolean;
  geminiEnabled: boolean;
  ollamaEnabled: boolean;
  lmStudioEnabled: boolean;
  llamaCppEnabled: boolean;
  mlxEnabled: boolean;
  telegramBotToken: string | null;
  telegramChatId: string | null;
}

export interface GeneratedAsset {
  id: string;
  projectId: string;
  taskId: string;
  agentType: AgentType;
  assetType: "image" | "video" | "audio" | "design" | "document";
  name: string;
  description: string;
  filePath: string;
  mimeType: string | null;
  fileSize: number | null;
  status: string;
  version: number;
  createdAt: string;
}

export interface PublishingChannel {
  id: string;
  name: string;
  channelType: "medium" | "wordpress" | "twitter" | "linkedin" | "devTo";
  isEnabled: boolean;
  defaultTags: string;
  createdAt: string;
}

export interface Publication {
  id: string;
  assetId: string;
  projectId: string;
  channelId: string;
  status: "scheduled" | "publishing" | "published" | "failed";
  publishedUrl: string | null;
  createdAt: string;
}
