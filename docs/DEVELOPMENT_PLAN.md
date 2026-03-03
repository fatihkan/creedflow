# CreedFlow Development Plan

> Last updated: 2026-03-03

## Overview

This document outlines the phased development roadmap for CreedFlow v1.4.0 and beyond. Issues are organized by dependency order, effort, and impact.

---

## Phase 1: Core Engine Hardening (Week 1-2) — COMPLETED

Foundation work — makes everything else more reliable.

| Order | Issue | Effort | Status |
|-------|-------|--------|--------|
| 1.1 | #142 Backend Health Monitoring | 3 days | Done |
| 1.2 | #143 Rate Limit Detection and Handling | 3 days | Done |
| 1.3 | #171 MCP Server Health Check and Connection Monitor | 3 days | Done |
| 1.4 | #144 In-App Notification Center | 2 days | Done |

**Delivered:**
- `BackendHealthMonitor` actor with periodic checks (60s interval, 5s timeout)
- `RateLimitDetector` with regex patterns + exponential backoff in `RetryPolicy`
- `MCPHealthMonitor` actor with connection tests (120s interval)
- `NotificationService` + `AppNotification` model + toast overlay + notification panel
- DB migration v20: `appNotification` + `healthEvent` tables with indexes
- Health dots in Settings (backend + MCP sections)

---

## Phase 2: UI Foundation (Week 2-3) — COMPLETED

Core UI improvements that affect all views.

| Order | Issue | Effort | Status |
|-------|-------|--------|--------|
| 2.1 | #145 Search and Filter on All List Views | 2 days | Done |
| 2.2 | #150 Loading Skeleton States and Progress Indicators | 2 days | Done |
| 2.3 | #147 Dark/Light Mode Toggle | 1 day | Done |
| 2.4 | #148 Keyboard Shortcuts Help Overlay | 1 day | Done |
| 2.5 | #158 Task Duplication | 0.5 day | Done |

**Delivered:**
- `SearchBar` component (React) + inline search bars (Swift) on Projects, Tasks, Reviews, Deploys, Agents, Archive
- `Skeleton`, `SkeletonCard`, `SkeletonRow` loading components (React); ProgressView retained (Swift)
- `themeStore` (Zustand + localStorage, React) + `@AppStorage("appearanceMode")` with NSApp.appearance (Swift)
- `KeyboardShortcutsOverlay` (React) + `KeyboardShortcutsView` (Swift) triggered by Cmd+?
- "Duplicate" in task context menu (both Rust command + Swift DB write)

---

## Phase 3: Project Features (Week 3-4)

Features that directly improve the project management experience.

| Order | Issue | Effort | Dependency |
|-------|-------|--------|------------|
| 3.1 | #168 Project Time Tracking and Duration Analytics | 3 days | None |
| 3.2 | #170 Project Export as ZIP | 2 days | None |
| 3.3 | #156 Project Templates | 2 days | None |
| 3.4 | #157 Task Comments and Notes | 2 days | None |
| 3.5 | #159 Prompt History per Task | 1 day | None |

**Why this order:**
- #168 (time tracking) adds `completedAt` to Project model — do first before other model changes
- #170 (export) uses project data including the new time fields
- #156 (templates) and #157 (comments) are independent
- #159 (prompt history) is small and self-contained

**Deliverables:**
- Project stats card (elapsed, work, idle time), per-agent breakdown, live timer
- DB migration (v21): `project.completedAt`, `taskComment` table, `taskPromptHistory` table
- `ProjectExporter` service + ZIP creation
- 6+ built-in project templates
- Comment system on tasks
- Prompt history tab in task detail

---

## Phase 4: Advanced UI (Week 4-5)

Visual polish and power-user features.

| Order | Issue | Effort | Dependency |
|-------|-------|--------|------------|
| 4.1 | #167 Git Graph UI Improvements | 3 days | None |
| 4.2 | #151 Analytics and Statistics Dashboard | 3 days | #168 (uses time data) |
| 4.3 | #149 Batch Task Operations | 2 days | None |
| 4.4 | #169 App Update Checker via GitHub Releases | 1 day | None |

**Why this order:**
- #167 (git graph) is a standalone visual feature — big impact
- #151 (analytics) benefits from time tracking data (#168)
- #149 (batch ops) is independent
- #169 (update checker) is small and self-contained

**Deliverables:**
- Commit detail panel, branch comparison, search, visual graph in Tauri
- Analytics dashboard: agent success rate, backend utilization, cost trends
- Multi-select mode with batch retry/cancel/priority
- `UpdateChecker` service + update banner

---

## Phase 5: Linux/Tauri Parity (Week 5-7)

Bring Tauri app to feature parity with macOS.

| Order | Issue | Effort | Dependency |
|-------|-------|--------|------------|
| 5.1 | #146 Inconsistent Error Handling in Tauri/React | 2 days | None |
| 5.2 | #152 Publishing Channel UI for Tauri/Linux | 2 days | None |
| 5.3 | #153 Prompt Chain Editor for Tauri/Linux | 2 days | None |
| 5.4 | #154 Prompt Version Diff View for Tauri/Linux | 2 days | None |
| 5.5 | #155 MCP Config Generation for Tauri/Linux | 2 days | #171 (MCP health) |

**Why this order:**
- #146 (error handling) is a bug fix — do first, makes debugging easier
- #152-#155 are independent parity features, can be parallelized
- #155 (MCP config) benefits from #171 health check infrastructure

**Deliverables:**
- Global toast system + error boundary in React
- Publishing channel settings + publish dialog
- Prompt chain create/edit/reorder UI
- Side-by-side prompt version diff
- MCP config generator + connection tester

---

## Phase 6: Polish & v1.5.0 (Week 8+)

Future improvements after v1.4.0 release.

| Order | Issue | Effort | Dependency |
|-------|-------|--------|------------|
| 6.1 | #163 Accessibility (a11y) | 3 days | None |
| 6.2 | #162 Localization (i18n) | 5 days | None |
| 6.3 | #164 Undo/Redo Support | 3 days | None |
| 6.4 | #161 Webhook and API Triggers | 3 days | None |
| 6.5 | #160 Side-by-Side Backend Comparison | 2 days | None |
| 6.6 | #165 Font Size Preference | 0.5 day | None |
| 6.7 | #166 Database Maintenance UI | 1 day | None |
| 6.8 | #47 Web Dashboard for Project Monitoring | TBD | SaaS phase |

---

## Summary

| Phase | Focus | Issues | Target |
|-------|-------|--------|--------|
| **Phase 1** | Engine Hardening | #142, #143, #171, #144 | **DONE** |
| **Phase 2** | UI Foundation | #145, #150, #147, #148, #158 | **DONE** |
| **Phase 3** | Project Features | #168, #170, #156, #157, #159 | Week 3-4 |
| **Phase 4** | Advanced UI | #167, #151, #149, #169 | Week 4-5 |
| **Phase 5** | Linux Parity | #146, #152, #153, #154, #155 | Week 5-7 |
| **Phase 6** | Polish (v1.5.0) | #163, #162, #164, #161, #160, #165, #166, #47 | Week 8+ |

**v1.4.0 scope:** Phase 1-5 (24 issues)
**v1.5.0 scope:** Phase 6 (8 issues)

---

## Dependency Graph

```
Phase 1 (Engine)
  #142 Backend Health ──┬──► #143 Rate Limit
                        ├──► #171 MCP Health ──► #155 MCP Config (Tauri)
                        └──► #144 Notifications

Phase 2 (UI Foundation)
  #145 Search ──────────── independent
  #150 Loading States ──── independent
  #147 Dark Mode ───────── independent
  #148 Shortcuts ───────── independent
  #158 Task Duplicate ──── independent

Phase 3 (Project)
  #168 Time Tracking ──┬──► #151 Analytics Dashboard
                       └──► #170 Export ZIP
  #156 Templates ───────── independent
  #157 Comments ────────── independent
  #159 Prompt History ──── independent

Phase 4 (Advanced UI)
  #167 Git Graph ───────── independent
  #149 Batch Ops ───────── independent
  #169 Update Checker ──── independent

Phase 5 (Tauri Parity)
  #146 Error Handling ──── do first (debugging)
  #152 Publishing ──────── independent
  #153 Prompt Chains ───── independent
  #154 Prompt Diff ─────── independent
```

---

## Release Checklist

### Before v1.4.0 Release
- [x] Phase 1 issues closed (#142, #143, #171, #144)
- [x] Phase 2 issues closed (#145, #150, #147, #148, #158)
- [ ] Phase 3-5 issues closed
- [ ] `swift build` — 0 errors
- [ ] `pnpm tauri build` — 0 errors
- [ ] Bump version to v1.4.0 (Info.plist, tauri.conf.json, package.json)
- [ ] Update CHANGELOG.md
- [ ] Update README.md "What's New" section
- [ ] Create GitHub release with artifacts
- [ ] Test on fresh macOS 14+ install
- [ ] Test on Ubuntu 22.04+
