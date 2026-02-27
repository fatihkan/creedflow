# CreedFlow Social Media Content

## Twitter Thread (5 tweets)

### Tweet 1 (Main)

I built an AI orchestration platform that turns a single project description into a fully working codebase.

11 AI agents. 7 backends. One app.

CreedFlow is now open source.

github.com/fatihkan/creedflow

#opensource #ai #developer #macos

---

### Tweet 2

How it works:

"Build a todo app with React + Node.js"
→ Analyzer creates architecture docs + ER diagrams
→ Coder writes code on feature branches
→ Reviewer scores it (AI code review)
→ Deploy with one click

All autonomous. All local.

---

### Tweet 3

Not just code — CreedFlow handles creative work too.

ContentWriter generates articles with .md → .html, .txt, .pdf export.
ImageGenerator + VideoEditor produce real assets.
Publisher distributes to Medium, WordPress, Twitter, LinkedIn.

Every asset is versioned with SHA256 checksums.

---

### Tweet 4

7 AI backends, zero lock-in:

Cloud: Claude CLI · Codex · Gemini
Local: Ollama · LM Studio · llama.cpp · MLX

Smart routing with automatic fallback. If cloud is down, local LLMs take over. No API keys required for local.

---

### Tweet 5

CreedFlow v1.0.0 is live.

macOS native (Swift + SwiftUI)
Linux version in development

GitHub: github.com/fatihkan/creedflow

If you find it useful, buy me a coffee:
buymeacoffee.com/fatihkan

#buildinpublic #devtools #opensource

---

## LinkedIn Post

I spent months building an AI orchestration platform. Today I'm releasing it.

As a developer, I was tired of manually switching between AI tools, copy-pasting prompts, and managing outputs. So I built CreedFlow — a native macOS app that orchestrates multiple AI agents to handle entire software projects autonomously.

What does it do?

You describe a project in plain English. CreedFlow takes it from there:

1. Analyzer agent produces architecture docs, data models, Mermaid diagrams, and a full task breakdown
2. Coder agent writes code on feature branches
3. Reviewer agent does AI code review with scoring
4. Creative agents generate images, videos, designs, and documents
5. Publisher agent distributes content to Medium, WordPress, Twitter, LinkedIn
6. Everything deploys locally via Docker or direct process

The tech behind it:

- 11 specialized AI agents, each with their own role and capabilities
- 7 AI backends: Claude, Codex, Gemini (cloud) + Ollama, LM Studio, llama.cpp, MLX (local)
- Smart routing — if a cloud backend is unavailable, local LLMs take over automatically
- Built with Swift 6.0 + SwiftUI, runs entirely on your machine
- MCP server with 13 tools for extensibility

What I learned:

The hardest part wasn't the AI integration — it was the orchestration. Managing task dependencies, handling retries, streaming output from multiple CLI processes, and keeping everything in sync across 11 agents required careful architecture.

Building this taught me that the future isn't a single AI doing everything. It's specialized agents collaborating, each doing what they're best at.

What's next:

- Linux desktop app (Tauri + React) — already in development
- Community contributions and feedback

CreedFlow v1.0.0 is live on GitHub: github.com/fatihkan/creedflow

If you're a developer who works with AI tools daily, I'd love your feedback.

#opensource #ai #developer #devtools #buildinpublic #macos #swift

---

## Screenshot Plan

| # | Screen | Description |
|---|--------|-------------|
| 1 | Setup Wizard | First launch, backend detection, green "installed" indicators |
| 2 | Project Creation | Empty project + description input |
| 3 | Task Board (Kanban) | Tasks in Queued/InProgress/Passed columns |
| 4 | Analyzer Output | Architecture doc or Mermaid diagram rendered |
| 5 | Agent Status | Orchestrator running, active agents visible |
| 6 | Assets Panel | Grid view with generated files (md, html, pdf) |
| 7 | Asset Detail Sheet | Asset preview + version history |
| 8 | Sidebar | Full sidebar — brand header, sections, Buy me a coffee |
| 9 | Review | Reviewer result — score, verdict, issues |
| 10 | Prompts Library | Prompt list, categories |

## Video Plan

**Duration:** 60-90 seconds

| Time | Scene | Content |
|------|-------|---------|
| 0-5s | Logo + tagline | "CreedFlow — AI Orchestration Platform" |
| 5-15s | Project creation | Typing "Todo app with React + Node.js" |
| 15-25s | Analyzer running | Tasks appearing, kanban filling up |
| 25-35s | Coder + Reviewer | Code being written, review score showing |
| 35-45s | Creative pipeline | Assets generated, format variants visible |
| 45-55s | Deploy | Docker deploy, success message |
| 55-65s | Backend settings | 7 backends visible, fallback explanation |
| 65-75s | Closing | GitHub URL + "Buy me a coffee" + #opensource |

**Recording:** macOS built-in (Cmd+Shift+5) or OBS
**Editing:** iMovie or DaVinci Resolve (free)
**Music:** Uppbeat or Pixabay (royalty-free)
