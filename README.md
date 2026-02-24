# CreedFlow

AI-powered project orchestration platform for macOS. Describe a project in natural language — CreedFlow analyzes it, creates tasks, routes them to AI backends, reviews code, and deploys.

## How It Works

```
You: "Todo app with React + Node.js + SQLite"
  ↓
CreedFlow: Analyzer agent decomposes into features & tasks
  ↓
CreedFlow: Routes tasks to Claude / Codex / Gemini backends
  ↓
CreedFlow: Coder agents write code, open branches per task
  ↓
CreedFlow: Reviewer agent scores code (AI review + security scan)
  ↓
CreedFlow: Telegram notification → You approve → Deploy
```

## Features

- **10 AI Agents** — Analyzer, Coder, Reviewer, Tester, DevOps, Monitor, ContentWriter, Designer, ImageGenerator, VideoEditor
- **3 CLI Backends** — Claude, Codex, Gemini with round-robin routing
- **Kanban Board** — Drag-and-drop task management with live agent output
- **Dependency Graph** — Tasks execute in correct order (e.g., DB before API before UI)
- **Auto-Retry** — Failed tasks retry up to 3 times before escalating
- **Cost Tracking** — Per-task token usage and cost breakdown by backend
- **Local Deploy** — Docker, Docker Compose, or direct process execution
- **MCP Server** — Query project state from external tools via `creedflow://` URIs
- **Telegram Notifications** — Task completion, review results, deploy status
- **Prompt Library** — Versioning, chaining, tagging, effectiveness tracking

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 6.0 |
| UI | SwiftUI (macOS 14+) |
| Database | SQLite via GRDB.swift |
| AI Backends | Claude CLI, Codex CLI, Gemini CLI |
| MCP | modelcontextprotocol/swift-sdk |
| Deployment | Docker / Docker Compose / Direct Process |
| Notifications | Telegram Bot API |

## Build & Run

```bash
# Build
cd CreedFlow && swift build

# Run the app
.build/debug/CreedFlow

# Run tests (38 tests)
.build/debug/CreedFlowTests

# Package as .app bundle
./Scripts/package-app.sh

# Package as DMG
./Scripts/package-app.sh --dmg
```

**Requirements:** macOS 14+, Swift 6.0, at least one AI CLI installed (claude, codex, or gemini).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     macOS App (SwiftUI)                      │
│  ┌──────────┐  ┌──────────────┐  ┌────────────────────────┐│
│  │ Sidebar   │  │ Task Board   │  │ Detail Panel           ││
│  │ Projects  │  │ (Kanban)     │  │ Live Output / Review   ││
│  └──────────┘  └──────────────┘  └────────────────────────┘│
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    Engine (Orchestrator)                      │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐ │
│  │ Task Queue   │  │ Backend      │  │ Agent Scheduler    │ │
│  │ (Priority +  │  │ Router       │  │ (Concurrency)      │ │
│  │  Dependencies)│ │ (Round-Robin)│  │                    │ │
│  └─────────────┘  └──────────────┘  └────────────────────┘ │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    CLI Backends (Process)                     │
│                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │ Claude   │    │ Codex    │    │ Gemini   │              │
│  │ CLI      │    │ CLI      │    │ CLI      │              │
│  │ (MCP,    │    │ (exec    │    │ (-p -y   │              │
│  │  tools)  │    │  --auto) │    │  -o text)│              │
│  └──────────┘    └──────────┘    └──────────┘              │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    10 AI Agents                              │
│                                                              │
│  Analyzer → Coder → Reviewer → Tester → DevOps → Monitor   │
│  ContentWriter    Designer    ImageGenerator    VideoEditor  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    Storage & Services                         │
│  ┌───────────┐  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │ SQLite    │  │ Git      │  │ Docker   │  │ Telegram  │ │
│  │ (GRDB)    │  │ Service  │  │ Deploy   │  │ Bot       │ │
│  └───────────┘  └──────────┘  └──────────┘  └───────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Agents

| Agent | Backend | Timeout | Purpose |
|-------|---------|---------|---------|
| **Analyzer** | Any | 5 min | Decompose projects into features/tasks |
| **Coder** | Claude | 15 min | Write code, create branches/PRs |
| **Reviewer** | Claude | 5 min | AI code review with 0-10 scoring |
| **Tester** | Claude | 10 min | Generate and run tests |
| **DevOps** | Any | 10 min | Docker, CI/CD, infrastructure setup |
| **Monitor** | Any | 5 min | Health checks, log analysis, alerts |
| **ContentWriter** | Any | 10 min | Articles, docs, copy writing |
| **Designer** | Any | 10 min | Design specs and guidelines |
| **ImageGenerator** | Any | 5 min | Image prompt engineering |
| **VideoEditor** | Any | 10 min | Video editing specifications |

**Backend routing:** Agents requiring MCP/tools (Coder, Reviewer, Tester) use Claude only. Others round-robin across all enabled backends.

## Database

SQLite with 9 migrations, 15 models:

- **project** — Name, description, tech stack, project type, status
- **feature** — Grouped tasks within a project
- **agentTask** — Individual work items with priority, status, backend, cost
- **taskDependency** — DAG edges between tasks
- **review** — Score, verdict (pass/needsRevision/fail), issues, suggestions
- **deployment** — Environment, method (docker/compose/process), status
- **costTracking** — Per-task token usage and USD cost by backend
- **agentLog** — Timestamped execution logs
- **prompt** / **promptVersion** / **promptChain** / **promptChainStep** / **promptTag** / **promptUsage** — Prompt management system
- **mcpServerConfig** — External MCP server configurations

## MCP Server

CreedFlow runs as an MCP server (`CreedFlowMCPServer` binary) exposing:

**Tools:** create-project, create-task, update-task-status, get-project-tasks, run-analyzer, get-cost-summary, search-prompts

**Resources:** `creedflow://projects`, `creedflow://tasks/queue`, `creedflow://costs/summary`, `creedflow://agents/status`

## Project Structure

```
CreedFlow/
├── Package.swift
├── Sources/
│   ├── App/                          # App entry point
│   ├── CreedFlow/                    # Main library
│   │   ├── Database/                 # GRDB migrations + queries
│   │   ├── Engine/                   # Orchestrator, TaskQueue, Scheduler
│   │   ├── Models/                   # 15 domain models
│   │   ├── Services/
│   │   │   ├── Agents/               # 10 agent implementations
│   │   │   ├── CLI/                  # Backend router + adapters
│   │   │   ├── Claude/               # Claude process management
│   │   │   ├── Deploy/               # Local deployment service
│   │   │   ├── Git/                  # Git + GitHub integration
│   │   │   ├── MCP/                  # MCP bridge + config generator
│   │   │   └── Telegram/             # Bot notifications + polling
│   │   ├── Utilities/                # NDJSON parser, async helpers
│   │   └── Views/                    # SwiftUI views (42 files)
│   └── MCPServer/                    # Standalone MCP server
├── Tests/CreedFlowTests/             # 38 tests
├── Resources/                        # Info.plist, entitlements
└── Scripts/                          # .app packaging
```

## License

Proprietary. All rights reserved.
