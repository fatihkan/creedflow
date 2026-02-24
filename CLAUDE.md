# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**CreedFlow** is a macOS native AI orchestration platform (Swift + SwiftUI) that autonomously manages software projects. It analyzes project descriptions, decomposes them into tasks, routes work to multiple AI CLI backends (Claude, Codex, Gemini), runs automated review, and deploys locally — all from a native desktop app.

**Domain:** creedflow.com | **Bundle ID:** com.creedflow.app

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6.0 (language mode v5 per target) |
| UI | SwiftUI (macOS 14+) |
| Database | SQLite via GRDB.swift |
| AI Backends | Claude CLI, Codex CLI, Gemini CLI |
| MCP | modelcontextprotocol/swift-sdk 0.11.0 |
| Deployment | Docker / Docker Compose / Direct Process |
| Notifications | Telegram Bot API |
| Packaging | .app bundle via Scripts/package-app.sh |

## Build & Run

```bash
cd CodeForge && swift build          # Build (0 errors expected)
.build/debug/CreedFlow               # Run the app
.build/debug/CreedFlowTests          # Run 38 tests
.build/debug/CreedFlowMCPServer      # Run MCP server (stdio)
./Scripts/package-app.sh             # Create .app bundle
./Scripts/package-app.sh --dmg       # Create DMG installer
```

Platform: macOS 14+ (arm64). Database at `~/Library/Application Support/CreedFlow/creedflow.sqlite`.

## Architecture

### SPM Package (CodeForge/)

4 targets in Package.swift:
- **CreedFlowLib** — Main library (`Sources/CreedFlow/`)
- **CreedFlow** — App executable (`Sources/App/`)
- **CreedFlowMCPServer** — MCP server binary (`Sources/MCPServer/`)
- **CreedFlowTests** — Test suite (`Tests/CreedFlowTests/`)

### Multi-CLI Backend System

`CLIBackend` protocol with 3 implementations:
- **ClaudeBackend** — Wraps `ClaudeProcessManager`, supports MCP/tools/JSON schema
- **CodexBackend** — Spawns `codex exec "<prompt>" --full-auto --skip-git-repo-check`
- **GeminiBackend** — Spawns `gemini -p "<prompt>" -y -o text`

`BackendRouter` selects backend per task: agents with MCP needs get Claude, others get round-robin across enabled backends. Enable/disable via UserDefaults (`claudeEnabled`, `codexEnabled`, `geminiEnabled`).

### 10 AI Agents

All conform to `AgentProtocol` with `backendPreferences`:

| Agent | Backend | Timeout | MCP | Purpose |
|-------|---------|---------|-----|---------|
| Analyzer | anyBackend | 5min | - | Decompose projects into features/tasks |
| Coder | claudeOnly | 15min | creedflow | Write code, open branches/PRs |
| Reviewer | claudeOnly | 5min | creedflow | AI code review + scoring |
| Tester | claudeOnly | 10min | creedflow | Run tests in workspace |
| DevOps | default | 10min | - | Docker, CI/CD, infrastructure |
| Monitor | default | 5min | - | Health checks, log analysis |
| ContentWriter | anyBackend | 10min | - | Content/copy writing |
| Designer | anyBackend | 10min | - | Design specs/guidelines |
| ImageGenerator | anyBackend | 5min | - | Image prompt generation |
| VideoEditor | anyBackend | 10min | - | Video editing specs |

### Engine

- **Orchestrator** — Central loop: polls TaskQueue every 2s, selects backend via BackendRouter, dispatches via MultiBackendRunner, handles completion pipelines
- **TaskQueue** — SQLite-backed priority queue with transactional dequeue, dependency-aware (waits for upstream tasks to pass)
- **AgentScheduler** — Concurrency control, slot management
- **DependencyGraph** — Validates DAG, detects cycles
- **RetryPolicy** — Failed tasks auto-retry up to maxRetries (default 3)

### Database (SQLite via GRDB)

9 migrations (v1–v9). 15 models: `Project`, `Feature`, `AgentTask`, `TaskDependency`, `Review`, `AgentLog`, `Deployment`, `CostTracking`, `MCPServerConfig`, `Prompt`, `PromptVersion`, `PromptChain`, `PromptChainStep`, `PromptTag`, `PromptUsage`.

### MCP Integration

- **Agent → External MCP**: Agents declare `mcpServers`, `MCPConfigGenerator` creates temp config, passed via `--mcp-config`
- **CreedFlow as MCP Server**: `CreedFlowMCPServer` binary, 7 tools + 4 resources, stdio transport
- **URIs**: `creedflow://projects`, `creedflow://tasks/queue`, `creedflow://costs/summary`

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
Sources/CreedFlow/Services/Claude/ClaudeProcessManager.swift — Process spawning
Sources/CreedFlow/Services/ProcessTracker.swift     — Global child process cleanup
Sources/CreedFlow/Services/Agents/AgentProtocol.swift — Agent interface
Sources/CreedFlow/Services/Deploy/LocalDeploymentService.swift — Docker/process deploy
Sources/CreedFlow/Database/AppDatabase.swift        — Migrations v1–v9
Sources/CreedFlow/Views/ContentView.swift           — Main window layout
Sources/CreedFlow/Views/Tasks/TaskBoardView.swift   — Kanban board
Resources/Info.plist                                — App metadata
Scripts/package-app.sh                              — .app + DMG packaging
```

## Core Workflow

1. User creates project (natural language description) via UI
2. Analyzer agent decomposes into features + tasks with dependency graph
3. Tasks queued by priority, dispatched when dependencies met
4. BackendRouter selects Claude/Codex/Gemini per agent preferences
5. MultiBackendRunner streams output, captures result
6. On completion: Reviewer scores code (>= 7.0 PASS, 5.0-6.9 NEEDS_REVISION, < 5.0 FAIL)
7. Failed tasks auto-retry up to 3 times
8. Telegram notifications at key milestones
9. Deploy to staging/production via Docker or direct process
