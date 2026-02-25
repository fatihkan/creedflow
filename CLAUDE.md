# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**CreedFlow** is a macOS native AI orchestration platform (Swift + SwiftUI) that autonomously manages software projects. It analyzes project descriptions, decomposes them into tasks, routes work to multiple AI CLI backends (Claude, Codex, Gemini) with local LLM fallback (Ollama, LM Studio, llama.cpp, MLX), runs automated review, and deploys locally — all from a native desktop app.

**Domain:** creedflow.com | **Bundle ID:** com.creedflow.app

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6.0 (language mode v5 per target) |
| UI | SwiftUI (macOS 14+) |
| Database | SQLite via GRDB.swift |
| AI Backends | Claude CLI, Codex CLI, Gemini CLI + Ollama, LM Studio, llama.cpp, MLX |
| MCP | modelcontextprotocol/swift-sdk 0.11.0 |
| Deployment | Docker / Docker Compose / Direct Process |
| Notifications | Telegram Bot API |
| Packaging | .app bundle via Scripts/package-app.sh |

## Build & Run

```bash
cd CreedFlow && swift build          # Build (0 errors expected)
.build/debug/CreedFlow               # Run the app
.build/debug/CreedFlowTests          # Run 111 tests
.build/debug/CreedFlowMCPServer      # Run MCP server (stdio)
./Scripts/package-app.sh             # Create .app bundle
./Scripts/package-app.sh --dmg       # Create DMG installer
```

Platform: macOS 14+ (arm64). Database at `~/Library/Application Support/CreedFlow/creedflow.sqlite`.

## Architecture

### SPM Package (CreedFlow/)

4 targets in Package.swift:
- **CreedFlowLib** — Main library (`Sources/CreedFlow/`)
- **CreedFlow** — App executable (`Sources/App/`)
- **CreedFlowMCPServer** — MCP server binary (`Sources/MCPServer/`)
- **CreedFlowTests** — Test suite (`Tests/CreedFlowTests/`)

### Multi-CLI Backend System

`CLIBackend` protocol with 7 implementations:

**Cloud backends (preferred):**
- **ClaudeBackend** — Wraps `ClaudeProcessManager`, supports MCP/tools/JSON schema
- **CodexBackend** — Spawns `codex exec "<prompt>" --full-auto --skip-git-repo-check`
- **GeminiBackend** — Spawns `gemini -p "<prompt>" -y -o text`

**Local LLM backends (fallback):**
- **OllamaBackend** — Spawns `ollama run <model> "<prompt>"` (default model: `llama3.2`)
- **LMStudioBackend** — HTTP POST to `localhost:1234/v1/chat/completions` (OpenAI-compatible API)
- **LlamaCppBackend** — Spawns `llama-cli -m <model> -p "<prompt>" -n 4096` with native `-sys` flag; requires GGUF model file
- **MLXBackend** — Spawns `mlx_lm.generate --model <model> --prompt "<prompt>"` (Apple Silicon only)

Local backends are **not** in any agent's `preferred` list. They are picked up via `allUsableBackends()` fallback in BackendRouter when no preferred cloud backend is available. They default to disabled and must be opted-in via Settings.

`BackendRouter` selects backend per task with smart fallback:
1. If agent requires Claude features → try Claude first
2. Collect enabled+available backends from agent's preference list
3. If no preferred backend is usable → fall back to ANY active backend (including local LLMs)
4. Round-robin across the resulting pool
5. Returns `nil` only when zero backends are enabled and available system-wide

**Hard rules:** A disabled backend (UserDefaults `<type>Enabled`) or one whose CLI binary is missing is NEVER selected. Tasks are deferred (not skipped) when no backend is available. LlamaCppBackend also requires a valid GGUF model path. LMStudioBackend requires `localhost:1234` to be reachable.

### 11 AI Agents

All conform to `AgentProtocol` with `backendPreferences`:

| Agent | Backend | Timeout | MCP | Purpose |
|-------|---------|---------|-----|---------|
| Analyzer | anyBackend | 5min | - | Deep architecture analysis, data models, Mermaid diagrams, task decomposition |
| Coder | claudeOnly | 15min | creedflow | Write code, open branches/PRs |
| Reviewer | claudeOnly | 5min | creedflow | AI code review + scoring |
| Tester | claudeOnly | 10min | creedflow | Run tests in workspace |
| DevOps | default | 10min | - | Docker, CI/CD, infrastructure |
| Monitor | default | 5min | - | Health checks, log analysis |
| ContentWriter | claudePreferred | 10min | creedflow | Content/copy writing |
| Designer | claudePreferred | 10min | figma, creedflow | Design specs + Figma access |
| ImageGenerator | claudePreferred | 10min | dalle, stability, creedflow | AI image generation |
| VideoEditor | claudePreferred | 15min | runway, elevenlabs, creedflow | Video/audio generation |
| Publisher | claudePreferred | 10min | creedflow | Content distribution to channels |

### Engine

- **Orchestrator** — Central loop: polls TaskQueue every 2s, selects backend via BackendRouter, dispatches via MultiBackendRunner, handles completion pipelines
- **TaskQueue** — SQLite-backed priority queue with transactional dequeue, dependency-aware (waits for upstream tasks to pass)
- **AgentScheduler** — Concurrency control, slot management
- **DependencyGraph** — Validates DAG, detects cycles
- **RetryPolicy** — Failed tasks auto-retry up to maxRetries (default 3)

### Database (SQLite via GRDB)

13 migrations (v1–v13). 18 models: `Project`, `Feature`, `AgentTask`, `TaskDependency`, `Review`, `AgentLog`, `Deployment`, `CostTracking`, `MCPServerConfig`, `Prompt`, `PromptVersion`, `PromptChain`, `PromptChainStep`, `PromptTag`, `PromptUsage`, `GeneratedAsset`, `Publication`, `PublishingChannel`.

### MCP Integration

- **Agent → External MCP**: Agents declare `mcpServers`, `MCPConfigGenerator` creates temp config, passed via `--mcp-config`
- **Creative MCP Servers**: DALL-E, Figma, Stability AI, ElevenLabs, Runway — templates in `MCPServerTemplate.swift`
- **CreedFlow as MCP Server**: `CreedFlowMCPServer` binary, 13 tools + 5 resources, stdio transport
- **URIs**: `creedflow://projects`, `creedflow://tasks/queue`, `creedflow://costs/summary`, `creedflow://projects/{id}/assets`, `creedflow://publications`

### Process Lifecycle

`ProcessTracker` singleton registers all spawned CLI processes by PID. On `applicationWillTerminate`, all child processes receive SIGTERM — no orphans.

## Key Patterns

- `AgentTask` (not `Task`) to avoid `Swift.Task` collision
- `TaskDependency` junction table (not UUID arrays)
- `@Observable` ViewModels with GRDB `ValueObservation`
- `NDJSONParser` buffers partial JSON lines across pipe chunks
- Models use `package` access level for cross-target visibility
- `extractJSON()` in Orchestrator strips ANSI codes, handles markdown blocks, validates JSON before returning
- Backend field written to DB on dispatch (not just completion) so UI shows it during in_progress
- `BackendPreferences.claudePreferred` — prefers Claude for MCP but falls back to Codex/Gemini (and local LLMs if cloud is unavailable)
- Creative agents output structured JSON `{"assets": [...]}` for asset pipeline; fallback saves raw output as text
- Asset versioning via `parentAssetId` linked-list chain with SHA256 checksums
- Content publishing: `ContentPublishingService` actor polls for scheduled publications every 60s
- Publisher agent outputs `{"publications": [...]}` JSON; Orchestrator processes and records results
- Analyzer produces rich output: `architecture`, `dataModels[]`, `diagrams[]` (Mermaid), tasks with `acceptanceCriteria[]`, `filesToCreate[]`, `estimatedComplexity`
- Analyzer saves `docs/ARCHITECTURE.md` and `docs/diagrams/*.mmd` to project directory
- Task detail panel slides from the right side (not bottom) for better readability
- Deployment cards show project name; pending/in-progress deployments can be cancelled
- Setup wizard has a Dependencies step with one-click Homebrew install for system tools
- Editor detection checks `.app` bundle paths (VS Code, Cursor, Zed, Windsurf) in addition to `/usr/local/bin` symlinks

## Key File Paths

```
Sources/App/CreedFlowApp.swift                    — App entry point + AppDelegate
Sources/CreedFlow/Engine/Orchestrator.swift        — Central coordination loop
Sources/CreedFlow/Engine/TaskQueue.swift            — Priority queue with dependency tracking
Sources/CreedFlow/Services/CLI/BackendRouter.swift  — Multi-backend selection
Sources/CreedFlow/Services/CLI/MultiBackendRunner.swift — Generic task executor
Sources/CreedFlow/Services/CLI/ClaudeBackend.swift  — Claude CLI adapter
Sources/CreedFlow/Services/CLI/CodexBackend.swift   — Codex CLI adapter
Sources/CreedFlow/Services/CLI/GeminiBackend.swift  — Gemini CLI adapter
Sources/CreedFlow/Services/CLI/OllamaBackend.swift  — Ollama local LLM adapter
Sources/CreedFlow/Services/CLI/LMStudioBackend.swift — LM Studio HTTP API adapter
Sources/CreedFlow/Services/CLI/LlamaCppBackend.swift — llama.cpp CLI adapter
Sources/CreedFlow/Services/CLI/MLXBackend.swift      — MLX-LM CLI adapter (Apple Silicon)
Sources/CreedFlow/Services/Claude/ClaudeProcessManager.swift — Process spawning
Sources/CreedFlow/Services/ProcessTracker.swift     — Global child process cleanup
Sources/CreedFlow/Services/Agents/AgentProtocol.swift — Agent interface
Sources/CreedFlow/Services/Deploy/LocalDeploymentService.swift — Docker/process deploy
Sources/CreedFlow/Models/GeneratedAsset.swift         — Asset model with versioning + checksums
Sources/CreedFlow/Models/Publication.swift             — Publication tracking model
Sources/CreedFlow/Models/PublishingChannel.swift       — Publishing channel configuration
Sources/CreedFlow/Services/AssetStorageService.swift  — File storage + DB records for creative assets
Sources/CreedFlow/Services/AssetVersioningService.swift — Asset version chain + SHA256 checksums
Sources/CreedFlow/Services/ThumbnailGeneratorService.swift — QuickLook thumbnail generation
Sources/CreedFlow/Services/Publishing/ContentPublishingService.swift — Central publishing coordinator
Sources/CreedFlow/Services/Publishing/ContentExporter.swift — Markdown→HTML/plaintext/PDF export
Sources/CreedFlow/Services/Storage/LocalAssetStorageBackend.swift — Local filesystem storage backend
Sources/CreedFlow/Database/AppDatabase.swift        — Migrations v1–v13
Sources/CreedFlow/Services/DependencyInstaller.swift — System dependency detection + Homebrew install
Sources/CreedFlow/Views/ContentView.swift           — Main window layout (sidebar + content + right detail panel)
Sources/CreedFlow/Views/Tasks/TaskBoardView.swift   — Kanban board
Sources/CreedFlow/Views/Setup/SetupWizardView.swift — 6-step setup wizard
Resources/Info.plist                                — App metadata
Scripts/package-app.sh                              — .app + DMG packaging
```

## Core Workflow

1. User creates project (natural language description) via UI
2. Analyzer agent produces architecture overview, data models, Mermaid diagrams, features + tasks with acceptance criteria and dependency graph; saves `docs/ARCHITECTURE.md` and `docs/diagrams/*.mmd` to project directory
3. Tasks queued by priority, dispatched when dependencies met
4. BackendRouter selects Claude/Codex/Gemini per agent preferences (local LLMs as fallback)
5. MultiBackendRunner streams output, captures result
6. On completion: Reviewer scores code (>= 7.0 PASS, 5.0-6.9 NEEDS_REVISION, < 5.0 FAIL)
7. Creative agents: output parsed for assets → saved to `~/CreedFlow/projects/{name}/assets/` → thumbnails generated → review queued
8. Content writer completion: queues publisher task when publishing channels are configured
9. Publisher agent: distributes content to Medium, WordPress, Twitter, LinkedIn
10. Failed tasks auto-retry up to 3 times
11. Telegram notifications at key milestones
12. Deploy to staging/production via Docker or direct process
