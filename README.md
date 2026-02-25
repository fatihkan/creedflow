# CreedFlow

AI-powered project orchestration platform for macOS. Describe a project in natural language — CreedFlow analyzes it, creates tasks, routes them to cloud or local AI backends, reviews code, and deploys.

## How It Works

```
You: "Todo app with React + Node.js + SQLite"
  ↓
CreedFlow: Analyzer produces architecture docs, ER diagrams, data models, task breakdown
  ↓
CreedFlow: Routes tasks to Claude / Codex / Gemini (+ local LLM fallback)
  ↓
CreedFlow: Coder agents write code, open branches per task
  ↓
CreedFlow: Reviewer agent scores code (AI review + security scan)
  ↓
CreedFlow: Creative agents generate assets (images, videos, designs)
  ↓
CreedFlow: Publisher agent distributes content to Medium, WordPress, Twitter, LinkedIn
  ↓
CreedFlow: Telegram notification → You approve → Deploy
```

## Features

- **11 AI Agents** — Analyzer, Coder, Reviewer, Tester, DevOps, Monitor, ContentWriter, Designer, ImageGenerator, VideoEditor, Publisher
- **Deep Analysis** — Analyzer produces architecture docs, data models with field-level detail, Mermaid diagrams (ER, flowchart, sequence, class), tasks with acceptance criteria and file lists
- **7 AI Backends** — Claude, Codex, Gemini (cloud) + Ollama, LM Studio, llama.cpp, MLX (local) with smart routing and automatic fallback
- **Kanban Board** — Drag-and-drop task management with live agent output and right-side detail panel
- **Setup Wizard** — 6-step wizard with environment detection, one-click dependency install via Homebrew, MCP server configuration
- **Dependency Graph** — Tasks execute in correct order (e.g., DB before API before UI)
- **Auto-Retry** — Failed tasks retry up to 3 times before escalating
- **Asset Pipeline** — Creative agents produce images/videos/designs with versioning, checksums, and thumbnails
- **Content Publishing** — Publish to Medium, WordPress, Twitter, LinkedIn with scheduled publishing
- **Local Deploy** — Docker, Docker Compose, or direct process execution with cleanup and cancel support
- **MCP Server** — 13 tools + 5 resources via `creedflow://` URIs
- **Creative MCP** — DALL-E, Figma, Stability AI, ElevenLabs, Runway integrations
- **Telegram Notifications** — Task completion, review results, deploy status
- **Prompt Library** — Versioning, chaining, tagging, effectiveness-based selection
- **Smart Backend Routing** — Disabled or missing CLIs are never selected; tasks fall back to any active backend

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 6.0 |
| UI | SwiftUI (macOS 14+) |
| Database | SQLite via GRDB.swift (13 migrations, 18 models) |
| AI Backends | Claude CLI, Codex CLI, Gemini CLI + Ollama, LM Studio, llama.cpp, MLX |
| MCP | modelcontextprotocol/swift-sdk 0.11.0 |
| Deployment | Docker / Docker Compose / Direct Process |
| Notifications | Telegram Bot API |

## Build & Run

```bash
# Build
cd CreedFlow && swift build

# Run the app
.build/debug/CreedFlow

# Run tests (111 tests)
.build/debug/CreedFlowTests

# Run MCP server (stdio)
.build/debug/CreedFlowMCPServer

# Package as .app bundle
./Scripts/package-app.sh

# Package as DMG
./Scripts/package-app.sh --dmg
```

**Requirements:** macOS 14+, Swift 6.0, at least one AI backend available (claude, codex, gemini, ollama, lm studio, llama.cpp, or mlx).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     macOS App (SwiftUI)                      │
│  ┌──────────┐  ┌──────────────┐  ┌────────────────────────┐│
│  │ Sidebar   │  │ Task Board   │  │ Detail Panel (Right)   ││
│  │ Projects  │  │ (Kanban)     │  │ Live Output / Review   ││
│  └──────────┘  └──────────────┘  └────────────────────────┘│
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    Engine (Orchestrator)                      │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐ │
│  │ Task Queue   │  │ Backend      │  │ Agent Scheduler    │ │
│  │ (Priority +  │  │ Router       │  │ (Concurrency)      │ │
│  │  Dependencies)│ │ (Smart       │  │                    │ │
│  │              │  │  Fallback)   │  │                    │ │
│  └─────────────┘  └──────────────┘  └────────────────────┘ │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    AI Backends                                │
│                                                              │
│  Cloud (preferred):                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │ Claude   │    │ Codex    │    │ Gemini   │              │
│  │ CLI      │    │ CLI      │    │ CLI      │              │
│  │ (MCP,    │    │ (exec    │    │ (-p -y   │              │
│  │  tools)  │    │  --auto) │    │  -o text)│              │
│  └──────────┘    └──────────┘    └──────────┘              │
│                                                              │
│  Local LLMs (fallback):                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ Ollama   │  │ LM Studio│  │ llama.cpp│  │ MLX      │  │
│  │ (run)    │  │ (HTTP)   │  │ (CLI)    │  │ (Apple   │  │
│  │          │  │ :1234    │  │ + GGUF   │  │  Silicon)│  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    11 AI Agents                              │
│                                                              │
│  Analyzer → Coder → Reviewer → Tester → DevOps → Monitor   │
│  ContentWriter → Designer → ImageGenerator → VideoEditor    │
│  Publisher                                                   │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    Storage & Services                         │
│  ┌───────────┐  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │ SQLite    │  │ Asset    │  │ Content  │  │ Telegram  │ │
│  │ (GRDB)    │  │ Pipeline │  │ Publishing│ │ Bot       │ │
│  │           │  │ + Thumbs │  │ Service  │  │           │ │
│  └───────────┘  └──────────┘  └──────────┘  └───────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Agents

| Agent | Preference | Timeout | Purpose |
|-------|-----------|---------|---------|
| **Analyzer** | Any | 5 min | Architecture analysis, data models, diagrams, task decomposition |
| **Coder** | Claude (fallback: any) | 15 min | Write code, create branches/PRs |
| **Reviewer** | Claude (fallback: any) | 5 min | AI code review with 0-10 scoring |
| **Tester** | Claude (fallback: any) | 10 min | Generate and run tests |
| **DevOps** | Any | 10 min | Docker, CI/CD, infrastructure setup |
| **Monitor** | Any | 5 min | Health checks, log analysis, alerts |
| **ContentWriter** | Claude preferred | 10 min | Articles, docs, copy writing |
| **Designer** | Claude preferred | 10 min | Design specs + Figma access |
| **ImageGenerator** | Claude preferred | 10 min | AI image generation (DALL-E, Stability) |
| **VideoEditor** | Claude preferred | 15 min | Video/audio generation (Runway, ElevenLabs) |
| **Publisher** | Claude preferred | 10 min | Publish to Medium, WordPress, Twitter, LinkedIn |

**Backend routing:** Disabled or unavailable backends are never selected. Cloud backends are preferred; local LLMs (Ollama, LM Studio, llama.cpp, MLX) serve as automatic fallback when no cloud backend is available. Tasks only skip when zero backends are available.

## Database

SQLite with 13 migrations, 18 models:

- **project** — Name, description, tech stack, project type, status
- **feature** — Grouped tasks within a project
- **agentTask** — Individual work items with priority, status, backend, cost
- **taskDependency** — DAG edges between tasks
- **review** — Score, verdict (pass/needsRevision/fail), issues, suggestions
- **deployment** — Environment, method (docker/compose/process), status
- **costTracking** — Per-task token usage and USD cost by backend
- **agentLog** — Timestamped execution logs
- **generatedAsset** — Creative assets with versioning, checksums, thumbnails
- **publication** — Published content tracking (status, external URLs)
- **publishingChannel** — Channel configuration (Medium, WordPress, Twitter, LinkedIn)
- **prompt** / **promptVersion** / **promptChain** / **promptChainStep** / **promptTag** / **promptUsage** — Prompt management system
- **mcpServerConfig** — External MCP server configurations

## MCP Server

CreedFlow runs as an MCP server (`CreedFlowMCPServer` binary) exposing:

**Tools (13):** create-project, create-task, update-task-status, get-project-tasks, run-analyzer, get-cost-summary, search-prompts, list-assets, get-asset, list-asset-versions, approve-asset, list-publications, list-publishing-channels

**Resources (5):** `creedflow://projects`, `creedflow://tasks/queue`, `creedflow://costs/summary`, `creedflow://projects/{id}/assets`, `creedflow://publications`

## Project Structure

```
CreedFlow/
├── Package.swift
├── Sources/
│   ├── App/                          # App entry point
│   ├── CreedFlow/                    # Main library
│   │   ├── Database/                 # GRDB migrations v1–v13
│   │   ├── Engine/                   # Orchestrator, TaskQueue, Scheduler, ChainExecutor
│   │   ├── Models/                   # 18 domain models
│   │   ├── Services/
│   │   │   ├── Agents/               # 11 agent implementations
│   │   │   ├── CLI/                  # Backend router + 7 adapters (cloud + local LLM)
│   │   │   ├── Claude/               # Claude process management
│   │   │   ├── Deploy/               # Local deployment service
│   │   │   ├── Git/                  # Git + GitHub integration
│   │   │   ├── MCP/                  # MCP bridge + config generator
│   │   │   ├── Publishing/           # Content exporter + 4 publishers
│   │   │   ├── Storage/              # Asset storage backend
│   │   │   └── Telegram/             # Bot notifications + polling
│   │   ├── Utilities/                # NDJSON parser, async helpers
│   │   └── Views/                    # SwiftUI views
│   └── MCPServer/                    # Standalone MCP server (13 tools, 5 resources)
├── Tests/CreedFlowTests/             # 111 tests
├── Resources/                        # Info.plist, entitlements
└── Scripts/                          # .app + DMG packaging
```

## License

Proprietary. All rights reserved.
