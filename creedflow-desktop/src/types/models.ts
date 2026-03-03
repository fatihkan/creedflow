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
  stagingPrNumber: number | null;
  completedAt: string | null;
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

export interface Feature {
  id: string;
  projectId: string;
  name: string;
  description: string;
  priority: number;
  status: string;
  integrationPrNumber: number | null;
  createdAt: string;
  updatedAt: string;
}

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
  revisionPrompt: string | null;
  skillPersona: string | null;
  archivedAt: string | null;
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
  | "publisher"
  | "planner";

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

export interface AgentBackendOverrides {
  analyzer: string | null;
  coder: string | null;
  reviewer: string | null;
  tester: string | null;
  devops: string | null;
  monitor: string | null;
  contentWriter: string | null;
  designer: string | null;
  imageGenerator: string | null;
  videoEditor: string | null;
  publisher: string | null;
  planner: string | null;
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
  opencodeEnabled: boolean;
  telegramBotToken: string | null;
  telegramChatId: string | null;
  hasCompletedSetup: boolean;
  agentBackendOverrides: AgentBackendOverrides | null;
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
  sourceUrl: string | null;
  metadata: string | null;
  status: string;
  reviewTaskId: string | null;
  version: number;
  thumbnailPath: string | null;
  checksum: string | null;
  parentAssetId: string | null;
  createdAt: string;
  updatedAt: string;
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

export interface DeploymentInfo {
  id: string;
  projectId: string;
  environment: string;
  status: string;
  version: string;
  commitHash: string | null;
  deployedBy: string;
  deployMethod: string | null;
  port: number | null;
  containerId: string | null;
  processId: number | null;
  logs: string | null;
  fixTaskId: string | null;
  autoFixAttempts: number;
  createdAt: string;
  completedAt: string | null;
}

export interface DependencyStatus {
  name: string;
  displayName: string;
  category: string;
  installed: boolean;
  version: string | null;
  path: string | null;
}

export interface PackageManagerInfo {
  name: string;
  displayName: string;
  available: boolean;
}

export interface DetectedEditor {
  name: string;
  command: string;
  path: string;
}

export interface Prompt {
  id: string;
  title: string;
  content: string;
  source: string;
  category: string;
  contributor: string | null;
  isBuiltIn: boolean;
  isFavorite: boolean;
  version: number;
  createdAt: string;
  updatedAt: string;
}

export interface PromptVersion {
  id: string;
  promptId: string;
  version: number;
  content: string;
  changeNote: string | null;
  createdAt: string;
}

export interface PromptRecommendation {
  promptId: string;
  promptTitle: string;
  category: string;
  successRate: number;
  totalUses: number;
  avgReviewScore: number | null;
}

export interface PromptVersionDiff {
  versionA: PromptVersion;
  versionB: PromptVersion;
  diffLines: DiffLine[];
}

export interface DiffLine {
  lineType: "added" | "removed" | "unchanged";
  content: string;
  lineNumberA: number | null;
  lineNumberB: number | null;
}

export interface PromptChain {
  id: string;
  name: string;
  description: string;
  category: string;
  createdAt: string;
  updatedAt: string;
}

export interface PromptChainStep {
  id: string;
  chainId: string;
  promptId: string;
  stepOrder: number;
  transitionNote: string | null;
}

export interface PromptChainWithSteps extends PromptChain {
  steps: PromptChainStep[];
  stepCount: number;
}

export interface PromptEffectivenessStats {
  promptId: string;
  promptTitle: string;
  totalUses: number;
  successCount: number;
  failCount: number;
  avgReviewScore: number | null;
  successRate: number;
}

// ─── Chat ───────────────────────────────────────────────────────────────────

export type MessageRole = "user" | "assistant" | "system";

export interface ChatAttachment {
  name: string;
  path: string;
  isImage: boolean;
}

export interface ProjectMessage {
  id: string;
  projectId: string;
  role: MessageRole;
  content: string;
  backend?: string;
  costUsd?: number;
  durationMs?: number;
  metadata?: string;
  attachments?: string; // JSON-serialized ChatAttachment[]
  createdAt: string;
}

export interface TaskProposal {
  type: string;
  status: string;
  features: FeatureProposal[];
}

export interface FeatureProposal {
  name: string;
  description: string;
  tasks: TaskProposalItem[];
}

export interface TaskProposalItem {
  title: string;
  description: string;
  agentType: string;
  priority: number;
}

// ─── Notifications & Health ────────────────────────────────────────────────

export type NotificationCategory =
  | "backendHealth"
  | "mcpHealth"
  | "rateLimit"
  | "task"
  | "deploy"
  | "system";

export type NotificationSeverity = "info" | "warning" | "error" | "success";

export type HealthStatus = "healthy" | "degraded" | "unhealthy" | "unknown";

export interface AppNotification {
  id: string;
  category: NotificationCategory;
  severity: NotificationSeverity;
  title: string;
  message: string;
  metadata: string | null;
  isRead: boolean;
  isDismissed: boolean;
  createdAt: string;
}

export interface HealthEvent {
  id: string;
  targetType: "backend" | "mcp";
  targetName: string;
  status: HealthStatus;
  responseTimeMs: number | null;
  errorMessage: string | null;
  metadata: string | null;
  checkedAt: string;
}

// ─── Task Comments ──────────────────────────────────────────────────────────

export interface TaskComment {
  id: string;
  taskId: string;
  content: string;
  author: "user" | "system";
  createdAt: string;
}

// ─── Project Time Stats ─────────────────────────────────────────────────────

export interface ProjectTimeStats {
  elapsedMs: number;
  totalWorkMs: number;
  idleMs: number;
  agentBreakdown: AgentTimeStat[];
}

export interface AgentTimeStat {
  agentType: string;
  totalMs: number;
  taskCount: number;
}

// ─── Project Templates ──────────────────────────────────────────────────────

export interface ProjectTemplate {
  id: string;
  name: string;
  description: string;
  icon: string;
  techStack: string;
  projectType: ProjectType;
  features: TemplateFeature[];
}

export interface TemplateFeature {
  name: string;
  description: string;
  tasks: TemplateTask[];
}

export interface TemplateTask {
  agentType: AgentType;
  title: string;
  description: string;
  priority: number;
}

// ─── Prompt Usage (for task prompt history) ─────────────────────────────────

export interface PromptUsageRecord {
  id: string;
  promptId: string;
  promptTitle: string | null;
  projectId: string | null;
  taskId: string | null;
  chainId: string | null;
  agentType: string | null;
  outcome: string | null;
  reviewScore: number | null;
  usedAt: string;
}
