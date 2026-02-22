# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**CodeForge** is an AI orchestration platform that autonomously manages multiple software projects. It analyzes project descriptions, decomposes them into tasks, writes code via AI agents, runs automated testing and review, and deploys with human approval via Telegram.

The project is in the **pre-code architecture phase** — the README.md contains the full architectural design document (in Turkish). No source code has been written yet.

## Planned Tech Stack

| Layer | Technology |
|-------|-----------|
| Orchestrator | Go |
| Agent Layer | Python (LLM integration via Claude API) |
| Database | PostgreSQL |
| Queue | Redis |
| Git | Gitea (self-hosted) |
| Deployment | Docker + Dokploy |
| Interface | Telegram Bot (go-telegram-bot-api) |
| Monitoring | Prometheus + Grafana |

## Architecture (Three Layers)

1. **Telegram Interface** — User-facing control layer (`/new`, `/status`, `/approve`, `/deploy`, etc.)
2. **Orchestrator (Go)** — Central coordination: project management, task queue (priority-based), agent scheduling, git branch management, deploy pipeline, notifications
3. **Agent Layer (Python)** — Six specialized AI agents:
   - **Analyzer Agent** — Parses project descriptions into structured task lists with dependency graphs
   - **Coder Agent** — Writes code, opens branches/PRs per task
   - **Reviewer Agent** — AI code review + static analysis + security scanning
   - **Tester Agent** — Unit/E2E/load tests
   - **DevOps Agent** — Docker, CI/CD, infrastructure
   - **Monitor Agent** — Health checks, log analysis, alerts
4. **Infrastructure Layer** — PostgreSQL (state), Redis (queue), Git repos, Docker/K8s (execution)

## Core Workflow

Project description (natural language) → Analyzer decomposes into features/tasks with dependency graph → Tasks queued by priority → Coder agents execute in sandboxed Docker containers, one branch/PR per task → Reviewer agent runs static analysis + security scan + AI review + tests → Results reported via Telegram → Human approves → Deploy to staging/production

## Key Design Decisions

- Each agent runs in an isolated Docker container (2GB memory, 1 CPU, no-new-privileges)
- Each task produces exactly one atomic PR
- Tasks follow a dependency graph (e.g., backend tables before frontend pages, tests after implementation)
- Review scoring: >= 7.0 PASS, 5.0-6.9 NEEDS_REVISION, < 5.0 FAIL
- Failed tasks auto-retry up to 3 times before escalating
- All operations are audit-logged with token usage and cost tracking

## Database Schema

Defined in README.md Section 5. Core tables: `projects`, `features`, `tasks`, `reviews`, `agent_logs`, `deployments`, `cost_tracking`. Tasks use UUID PKs, JSONB for flexible config, and `UUID[]` for dependency tracking.

## MVP Roadmap Phases

1. Foundation — Go orchestrator, PostgreSQL, Telegram bot, Gitea, Redis
2. Analyzer Agent — Claude API integration, `/new` command
3. Coder Agent — Git branch management, code generation, PR creation
4. Reviewer + Tester — AI review pipeline, static analysis, test execution
5. Deploy Pipeline — Staging/production deploy via Dokploy, rollback
6. SaaS — Multi-tenant, web dashboard, billing

## Language Note

The README and project context are in Turkish. The platform targets the Turkish market (TL pricing, Turkish natural language support, Telegram-first approach).
