# Changelog

All notable changes to CreedFlow are documented in this file.

## [v1.4.0] — 2026-03-03

### Added

#### Phase 1: Core Engine Hardening (#142, #143, #171, #144)
- **Backend Health Monitoring** — `BackendHealthMonitor` actor checks all CLI backends every 60s (--version with 5s timeout, LMStudio via HTTP)
- **Rate Limit Detection** — `RateLimitDetector` with regex patterns for 429, "rate limit", "RESOURCE_EXHAUSTED"; exponential backoff (60s base, 600s max)
- **MCP Health Monitoring** — `MCPHealthMonitor` actor checks enabled MCP servers every 120s (spawns process, checks if stays running)
- **In-App Notification Center** — `NotificationService` actor with `AppNotification` model, toast overlay (top-right, auto-dismiss 5s), notification panel (bell icon in sidebar), mark-read/dismiss
- **Health status dots** in Settings for backends and MCP servers (green=healthy, red=unhealthy)
- New DB migration (v20): `appNotification` and `healthEvent` tables with indexes

#### Phase 2: UI Foundation (#145, #150, #147, #148, #158)
- **Search & Filter on all list views** — Reusable `SearchBar` component (React) + inline search pattern (Swift) on Projects, Tasks, Reviews, Deployments, Agents, Archive
- **Skeleton loading states** — `Skeleton`, `SkeletonCard`, `SkeletonRow` components replacing "Loading..." text (React)
- **Dark/Light Mode toggle** — System/Light/Dark with `localStorage` persistence (React) and `@AppStorage` + `NSApp.appearance` (Swift)
- **Keyboard Shortcuts Overlay** — `Cmd+?` opens modal listing all navigation (Cmd+1-8) and action (Escape, Cmd+?) shortcuts
- **Task Duplication** — "Duplicate" in task context menu: copies all task fields with fresh UUID, "Copy of " title prefix, status reset to Queued

### Changed
- Orchestrator now health-aware: skips unhealthy backends during dispatch
- Rate-limit catch branch with longer backoff in retry pipeline
- In-app notifications alongside Telegram for task/deploy/review events
- `MultiBackendRunner` detects rate limits in error output
- `RetryPolicy` extended with `isRateLimited()` and `rateLimitBackoff()`
- Empty state messages now distinguish "no data" vs "no search results" on ReviewApprovalView and DeployView

## [v1.3.0] — 2026-03-03

### Added
- **OpenClaw CLI backend** — New cloud backend with auto-detection and smart routing
- **Qwen Code CLI backend** — Additional AI backend with editor install buttons in setup wizard
- **Planner agent** — New agent for project planning and task breakdown (12 agents total)
- **File & image attachments** in AI chat panel
- **Tauri AI backend streaming** wired up for Linux desktop
- **Resizable chat input** area
- **Persistent chat state** across navigation
- **CLI install buttons** — One-click install for AI CLIs directly from the setup wizard
- **Security section in README** — Best practices for AI-generated code safety
- **CONTRIBUTING.md** — Contribution guidelines and development setup
- **SECURITY.md** — Security policy and vulnerability reporting process
- **MIT License** added

### Fixed
- **Docker install error handling** — Exit code detection with sudo/privilege error messages

### Changed
- Backend count: 7 → 9 (added OpenCode, OpenClaw)
- Agent count: 11 → 12 (added Planner)
- `.gitignore` hardened with `.env`, `*.pem`, `*.key`, `secrets.*`, `credentials.*` patterns
- Updated all documentation for 9 backends and 12 agents

## [v1.2.0] — 2026-03-02

### Added
- **AI Chat System** — Slide-in chat panel for AI-assisted task planning and brainstorming
- **Task Proposals** — AI suggests features and tasks inline; approve or reject with one click
- **Streaming Responses** — Real-time typing indicator with partial content display
- **OpenCode backend** — New cloud CLI backend
- **Import Existing Projects** — Point to an existing directory instead of creating a new one
- **Project Creation Wizard** — Step-by-step guided project setup with tech stack detection
- **Project Docs Export** — Bundle architecture docs, diagrams, and README into a single file
- **Project-Type-Aware Analysis** — Analyzer produces specialized output per project type
- **Prompt Import/Export** — Share prompts as JSON files across teams
- **Version Diff** — Side-by-side comparison of prompt versions with line-level diff
- **Prompt Recommender** — AI-powered prompt suggestions based on success rate
- **CLI Usage Tracking** — Real-time API usage monitoring via Anthropic/OpenAI admin APIs
- **MCP Requirements Checker** — Auto-detect missing MCP servers based on project type
- **Creative AI Services** — HeyGen, Replicate, Leonardo.AI MCP templates
- **Skill Persona** — Assign personality/expertise profiles to tasks
- **Swift/Rust feature parity** across macOS and Linux platforms

### Fixed
- ContentWriter consistency pipeline with backend-agnostic parsing
- Project creation crash when directory already exists
- Anthropic usage API endpoint and response field names

## [v1.1.0] — 2026-02-27

### Added
- **Linux desktop app** — Full-featured Tauri + React desktop app
- **Full macOS feature parity** — Grouped sidebar, task detail panel, project detail views
- **Full Linux feature parity** — Asset gallery, prompts, MCP server, costs, deploy, thumbnails, PDF export
- **App logo** in sidebar header

### Fixed
- Codex CLI output parsing — use `--output-last-message` for clean output
- Linux CI missing `libayatana-appindicator3-dev` dependency
- Tauri dev startup with default-run and idempotent migrations

### Changed
- Removed payment/subscription UI
- Hidden cost tracking from UI

## [v1.0.0] — 2026-02-27

### Added
- **11 AI Agents** — Analyzer, Coder, Reviewer, Tester, DevOps, Monitor, ContentWriter, Designer, ImageGenerator, VideoEditor, Publisher
- **7 AI Backends** — Claude, Codex, Gemini (cloud) + Ollama, LM Studio, llama.cpp, MLX (local)
- **Smart Backend Router** — Round-robin selection with automatic fallback
- **Kanban Board** — Drag-and-drop task management with live agent output
- **Setup Wizard** — Environment detection, one-click dependency install via Homebrew
- **MCP Server** — 13 tools + 5 resources via `creedflow://` URIs
- **Creative MCP** — DALL-E, Figma, Stability AI, ElevenLabs, Runway integrations
- **Asset Pipeline** — Creative agents produce images/videos/designs with versioning and SHA256 checksums
- **Content Publishing** — Medium, WordPress, Twitter, LinkedIn with scheduled publishing
- **Prompt Library** — Versioning, chaining, tagging, effectiveness tracking
- **Git Integration** — Feature branches, auto-commit, auto-merge, three-branch progression (dev → staging → main)
- **Local Deploy** — Docker, Docker Compose, or direct process execution
- **Telegram Notifications** — Task completion, review results, deploy status
- **Deep Analysis** — Architecture docs, data models, Mermaid diagrams, tasks with acceptance criteria
- **Multi-format export** — .md → .html, .txt, .pdf from ContentWriter output
- **Task archive system** — Soft-delete and permanent delete
- **Git Graph visualization** — Branch lanes, merge curves, commit history
- **Per-agent CLI backend preferences** with Settings UI
- **Multi-task parallel dispatch** with configurable concurrency
- **Deploy failure auto-recovery** pipeline

[v1.4.0]: https://github.com/fatihkan/creedflow/compare/v1.3.0...v1.4.0
[v1.3.0]: https://github.com/fatihkan/creedflow/compare/v1.2.0...v1.3.0
[v1.2.0]: https://github.com/fatihkan/creedflow/compare/v1.1.0...v1.2.0
[v1.1.0]: https://github.com/fatihkan/creedflow/compare/v1.0.0...v1.1.0
[v1.0.0]: https://github.com/fatihkan/creedflow/releases/tag/v1.0.0
