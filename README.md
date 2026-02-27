# CreedFlow

**AI-powered project orchestration platform.** Describe a project in natural language — CreedFlow analyzes it, creates tasks, routes them to cloud or local AI backends, reviews code, generates creative assets, publishes content, and deploys.

[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](https://github.com/fatihkan/creedflow/releases)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-Proprietary-blue)](#license)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/fatihkan)

---

## Download

| Platform | Status | Download |
|----------|--------|----------|
| **macOS** (Apple Silicon) | v1.0.0 | [Download DMG](https://github.com/fatihkan/creedflow/releases/latest) |
| **Linux** | In Development | Coming soon (Tauri + React) |

> **Requirements:** macOS 14+, at least one AI backend available (Claude CLI, Codex CLI, Gemini CLI, Ollama, LM Studio, llama.cpp, or MLX).

---

## How It Works

```
You: "Todo app with React + Node.js + SQLite"
  ↓
Analyzer → Architecture docs, ER diagrams, data models, task breakdown
  ↓
Router → Routes tasks to Claude / Codex / Gemini (+ local LLM fallback)
  ↓
Coder → Writes code, opens feature branches per task
  ↓
Reviewer → AI code review with 0-10 scoring
  ↓
Creative agents → Generate images, videos, designs, documents
  ↓
Publisher → Distributes content to Medium, WordPress, Twitter, LinkedIn
  ↓
Telegram notification → You approve → Deploy
```

## Features

- **11 AI Agents** — Analyzer, Coder, Reviewer, Tester, DevOps, Monitor, ContentWriter, Designer, ImageGenerator, VideoEditor, Publisher
- **Deep Analysis** — Architecture docs, data models with field-level detail, Mermaid diagrams (ER, flowchart, sequence, class), tasks with acceptance criteria and file lists
- **7 AI Backends** — Claude, Codex, Gemini (cloud) + Ollama, LM Studio, llama.cpp, MLX (local) with smart routing and automatic fallback
- **Kanban Board** — Drag-and-drop task management with live agent output
- **Setup Wizard** — 6-step wizard with environment detection, one-click dependency install via Homebrew
- **Asset Pipeline** — Creative agents produce images/videos/designs with versioning, checksums, and format variants (.md → .html, .txt, .pdf)
- **Content Publishing** — Publish to Medium, WordPress, Twitter, LinkedIn with scheduled publishing
- **Prompt Library** — Versioning, chaining, tagging, effectiveness-based selection
- **Git Integration** — Feature branches, auto-commit, auto-merge on review pass, three-branch progression (dev → staging → main)
- **Local Deploy** — Docker, Docker Compose, or direct process execution
- **MCP Server** — 13 tools + 5 resources via `creedflow://` URIs
- **Creative MCP** — DALL-E, Figma, Stability AI, ElevenLabs, Runway integrations
- **Telegram Notifications** — Task completion, review results, deploy status

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 6.0 |
| UI | SwiftUI (macOS 14+) |
| Database | SQLite via GRDB.swift |
| AI Backends | Claude CLI, Codex CLI, Gemini CLI + Ollama, LM Studio, llama.cpp, MLX |
| MCP | modelcontextprotocol/swift-sdk |
| Deployment | Docker / Docker Compose / Direct Process |
| Notifications | Telegram Bot API |

## Build from Source

```bash
cd CreedFlow && swift build
.build/debug/CreedFlow

# Package as DMG
./Scripts/package-app.sh --dmg
```

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
│  Cloud:  Claude CLI  ·  Codex CLI  ·  Gemini CLI            │
│  Local:  Ollama  ·  LM Studio  ·  llama.cpp  ·  MLX        │
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
│  SQLite (GRDB) · Asset Pipeline · Content Publishing        │
│  Telegram Bot · MCP Server · Git Branch Manager             │
└─────────────────────────────────────────────────────────────┘
```

## Agents

| Agent | Backend | Timeout | Purpose |
|-------|---------|---------|---------|
| Analyzer | Any | 5 min | Architecture analysis, data models, diagrams, task decomposition |
| Coder | Claude preferred | 15 min | Write code, create branches/PRs |
| Reviewer | Claude preferred | 5 min | AI code review with 0-10 scoring |
| Tester | Claude preferred | 10 min | Generate and run tests |
| DevOps | Any | 10 min | Docker, CI/CD, infrastructure setup |
| Monitor | Any | 5 min | Health checks, log analysis |
| ContentWriter | Claude preferred | 10 min | Articles, docs, copy writing + multi-format export |
| Designer | Claude preferred | 10 min | Design specs + Figma access |
| ImageGenerator | Claude preferred | 10 min | AI image generation (DALL-E, Stability) |
| VideoEditor | Claude preferred | 15 min | Video/audio generation (Runway, ElevenLabs) |
| Publisher | Claude preferred | 10 min | Medium, WordPress, Twitter, LinkedIn |

## MCP Server

CreedFlow also runs as an MCP server (`CreedFlowMCPServer` binary):

**Tools (13):** create-project, create-task, update-task-status, get-project-tasks, run-analyzer, get-cost-summary, search-prompts, list-assets, get-asset, list-asset-versions, approve-asset, list-publications, list-publishing-channels

**Resources (5):** `creedflow://projects`, `creedflow://tasks/queue`, `creedflow://costs/summary`, `creedflow://projects/{id}/assets`, `creedflow://publications`

## Support

If you find CreedFlow useful, consider supporting the project:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/fatihkan)

## License

Proprietary. All rights reserved.
