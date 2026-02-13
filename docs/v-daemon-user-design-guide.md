# Project Design & User Guide

## README

# v-daemon

A lightweight supervisor and developer harness for experimenting with a Director/Worker autonomous loop.

v-daemon provides small POSIX shell helpers to set up dependencies, run repository checks, and operate a simple supervisor + agent workflow. Optional native C/C++ components and CMake support are available but not required for most development.

**Status:** Early development — the long-term goal is a safe, iterative engine that summarizes the repository, generates prioritized tasks, and applies small, verifiable changes under automated governance. Decisions about what to implement are determined via automated discourse by code-review personas; the Director persona synthesizes votes and makes release decisions aligned with the project's prime directive. The system is designed to operate autonomously; human interaction is limited to starting and stopping the system and emergency intervention.

Recent updates (2026-02-13):

- Centralized env helpers: scripts/lib/env.sh (env_init) now sources console.sh, logger.sh, prompts.sh and is idempotent; scripts call env_init to avoid duplicate sourcing.
- Script hardening: portable fallbacks introduced for sed -i, ps (ps_fallback), timeout, and safer find/grep usage; update-docs now creates OUT/RAW directories and guards file reads.
- SKILL.md improvements: short descriptions were updated to improve Copilot CLI /skills discovery and context.


## Quickstart

1. Prepare your environment:

   ```sh
   sh scripts/setup.sh --yes
   ```

2. Run repository checks:

   ```sh
   sh scripts/setup.sh --check
   ```

3. Start the supervisor/daemon:

   ```sh
   sh scripts/run.sh [--monitor]
   ```

## Key scripts

- `scripts/setup.sh` — install or prepare dependencies and create `run/` and `logs/`
- `scripts/check.sh` — run repository checks (read-only by default)
- `scripts/run.sh` — start/stop/status the supervisor and daemon

## Requirements

- POSIX `sh` (bash/sh)
- CMake, Ninja, and a C/C++ toolchain only for native builds

## Development

- Prefer small, focused PRs; run `scripts/setup.sh` before pushing.
- Add tests under `build/` and integrate them into `scripts/setup.sh` and CI.

## Docs and resources

- Architecture: `docs/architecture.md`
- Agent docs: `AGENT.md` and `.github/skills/`
- Runtime config: `config/settings.toml`

## Contributing

- Open issues and PRs on GitHub. Keep changes minimal and document acceptance criteria.

- Governance: Decisions are made via automated discourse by the repository's code-review personas; the Director persona synthesizes votes and determines the iterative release cycle aligned with the project's prime directive (autonomous agent swarm that self-improves, optimizes, and evolves). Human interaction is limited to starting and stopping the system and emergency intervention; agent personas and the Director govern prioritization and acceptance.
- Never commit secrets.

## License

See the `LICENSE` file at the repository root.




---

## v-daemon Roadmap (Milestones M0 → M3+)

# v-daemon Roadmap (Milestones M0 → M3+)

This document groups work into high-level milestones and phases. It intentionally omits dates or time estimates and focuses on goals, deliverables, and the sequence of phases. Emphasis is on M0 (current work) and M1 (first running loop).

---

## Milestone M0 — Foundation & Stabilization (current)

Goal
- Stabilize the repository and agent tooling so the Director, Daemon, and skill scripts operate reliably, produce auditable outputs, and can be exercised in a looped workflow.

Overview / Phases
- Core stability: harden scripts (setup/run), ensure reliable PID/lock handling, add cleanup (--clean), centralize shared helpers and prompts, fix script injection issues.
- Observability & audits: standardize logs and JSONL audits (audits/), ensure autopilot summaries and plan artifacts are written to run/ and audits/ for debugging.
- Prompt centralization: move LLM prompts into scripts/lib/prompts.sh and update actions to use show_prompt to avoid inline prompt drift.
- Safe patch tooling: ensure patch-repo and patcher are consistent (script pushes by default), capture structured reports, and ensure failures are detectable and actionable by the agent.
- Docs and specs automation: ensure docs/specs/_template.md exists, generate/repair specs automatically from source, add docs build command to compile markdown and optionally produce PDF outputs.
- Acceptance criteria for M0: Director and Daemon can be started; autopilot summary runs and writes artifacts; prompt texts are centralized; patch-repo and patcher run and report; docs build path exists and generates files.

Immediate next tasks (M0 focus)
- Verify and remove any inline prompt text across the repo and use prompts.sh (done for known files).
- Run Director autopilot and confirm audit outputs; remove stale locks and log failures.
- Confirm patch-repo fails loudly when push cannot succeed and collect troubleshooting artifacts.
- Create or confirm docs/specs/_template.md and test docs.sh build flow (markdown → compiled guide → pdf via pandoc).

---

## Milestone M1 — Continuous Looping System (first autonomous loop)

Goal
- Run the system in a continuous loop without operator intervention: Director + Daemon repeatedly summarize, plan, and exercise safe sandbox operations while producing auditable artifacts.

Overview / Phases
- Reliable loop: make director/daemon resilient to restarts, crashes, and locks; improve process adoption and pidfile handling.
- Autopilot chain: autopilot summary → autopilot plan → select task → patcher/patch-repo (sandboxed) pipeline, with all outputs auditable and stored under run/ and audits/.
- Dry-run first: default behavior is sandbox-only or dry-run mode; commit/push gates require explicit permission or human approval.
- Monitoring & ops: add health checks, heartbeat reporting, log rotation, and clear operator-facing summaries in logs/ and audits/.
- Docs & guide: auto-generate design/user guide artifacts each loop iteration and keep a changelog of doc updates.
- Acceptance for M1: system runs continuously, produces summaries/plans, creates sandbox artifacts, and operators can inspect run/ and audits/ to validate behavior.

---

## Milestone M2 — Scaffolding for Automated Change

Goal
- Move from sandboxed/dry-run workflows toward safe, automated changes that can create PRs, run CI checks, and be human-reviewed and merged.

Overview / Phases
- PR automation: create sandbox branches, create deterministic commits, and open PRs with templated descriptions and linked audit artifacts.
- CI integration: wire PRs to automated CI/test runners and block merges until checks pass; surface CI results to audits and plan outputs.
- Safe merge policies: implement gating, protected-branch awareness, and rate-limiting for automated actors.
- Expanded skills: richer update-docs behavior (compare code ↔ docs, create/merge specs, remove stale docs), automated design guide updates.
- Tests & verification: add targeted unit and integration tests for scripts, patcher, and the Director autopilot workflow.

---

## Milestone M3+ — Self-Improving Agent Swarm (vision)

Goal
- Evolve into a robust, scalable swarm of cooperating agents that can adapt, propose improvements, and maintain the system while preserving human oversight, governance, and auditability.

Overview / Themes
- Distributed coordination: agent discovery, secure RPC/queues, and decentralized state or federation models.
- Learning & feedback: validated runtime feedback loops to let agents refine prompts, prioritize tasks, and reduce operator friction.
- Governance & safety: audit trails, human-in-the-loop controls, capability scoping, RBAC, and compliance features.
- Extensibility: plugin/skill ecosystem, shared templates, and improved docs/spec scaffolding for ecosystem contributors.

Notes & constraints
- M0 and M1 require explicit focus and must prioritize safety, auditable outputs, and clear operator controls.
- M2 is about scaffolding safe automation—not full autonomy; human review gates and CI must be enforced.
- M3+ is exploratory and subject to revision as findings from M0–M2 emerge.

---

How to use this roadmap
- Use M0 tasks as the active checklist for immediate engineering work. When M0 acceptance criteria are satisfied, transition to M1 phases and validate system loop behavior before expanding automation in M2.

Feedback or changes
- To revise scope or phase ordering, update this document under docs/ROADMAP.md and reflect task changes into the Director's next-steps workflows.


---

## Agents

# Agents

Shared helpers and conventions for agent scripts.

- Source `scripts/lib/actions.sh` to use shared functions.
- Place helper scripts under `scripts/agents/` or `scripts/lib/`.
- Keep agent scripts small, idempotent, and safe by default.
- Capture artifacts under `run/` and `logs/` for later inspection.


---

## Architecture & Vision

# Architecture & Vision

## Overview

v-daemon is a small supervisor and development harness to explore a Director/Worker autonomous loop. It prioritizes small, auditable shell-first workflows with optional native extensions.

## Components

- **Supervisor**: manages processes, PID files, restarts, and logs.
- **Director**: orchestrates planning cycles and assigns work.
- **Worker**: executes assigned tasks.
- **Scripts**: `scripts/setup.sh`, `scripts/setup.sh`, `scripts/run.sh`, and `scripts/lib/` provide developer workflows.
- **Configuration**: `config/settings.toml` controls runtime behavior.

## Principles

- Small and auditable: prefer POSIX shell for discoverability.
- Optional native: allow C/C++ components without requiring toolchains.
- Safe by default: sandbox execution; the Director operates autonomously by default and can be configured to require explicit operator consent for mutations.
- Testable: make changes verifiable via `scripts/setup.sh`.

## Runtime layout

- `run/`: PID files and runtime artifacts
- `logs/`: persistent logs
- `external/`: fetched dependencies
- `build/`: optional out-of-source builds

## Roadmap

- Stabilize the supervisor and add CI checks.
- Add a reference Director/Worker implementation and container images.
- Expand automation skills and CI integrations.


---

## Scripts

# Scripts

All scripts are POSIX `sh` with `#!/usr/bin/env sh` and should be executable (`chmod +x`).

## Common commands

- `sh scripts/setup.sh --yes` — prepare environment and optional dependencies.
- `sh scripts/setup.sh --check` — run repository checks (use in CI).
- `sh scripts/run.sh [--monitor]` — start/stop/status the supervisor and daemon; `--monitor` streams logs.

## Guidelines for new scripts

- Add a short header comment explaining purpose and usage.
- Avoid unguarded package installs; by default the Director will avoid network installs during automated runs; operator consent may be required in conservative deployments.
- Use `run/` and `logs/` for runtime artifacts.


---

## Purpose

---
name: docs
generated_by: docs.sh
generated_at: 20260213T175045Z
source: scripts/docs.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env bash

## Synopsis / Usage


## Reference
- Source: scripts/docs.sh


---

## Purpose

---
name: actions
generated_by: docs.sh
generated_at: 20260213T175045Z
source: scripts/lib/actions.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Director action helpers: autopilot summary (uses copilot CLI only; local fallback removed).

## Synopsis / Usage


## Reference
- Source: scripts/lib/actions.sh


---

## Purpose

---
name: config
generated_by: docs.sh
generated_at: 20260213T175045Z
source: scripts/lib/config.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Configuration loader: reads ./config/settings.toml and exposes runtime variables.
# Usage: . "$REPO_ROOT/scripts/lib/config.sh"; config_init "$REPO_ROOT"

## Synopsis / Usage


## Reference
- Source: scripts/lib/config.sh


---

## Purpose

---
name: console
generated_by: docs.sh
generated_at: 20260213T175045Z
source: scripts/lib/console.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Console helpers: print status and truncated excerpts to console (stderr).

## Synopsis / Usage


## Reference
- Source: scripts/lib/console.sh


---

## Purpose

---
name: daemon
generated_by: docs.sh
generated_at: 20260213T175045Z
source: scripts/lib/daemon.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Minimal daemon loop. Replace loop body with self-improving logic later.

## Synopsis / Usage


## Reference
- Source: scripts/lib/daemon.sh


---

## Purpose

---
name: director
generated_by: docs.sh
generated_at: 20260213T175045Z
source: scripts/lib/director.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Director agent: coordinates worker agents (minimal stub)

## Synopsis / Usage


## Reference
- Source: scripts/lib/director.sh


---

## Purpose

---
name: env
generated_by: docs.sh
generated_at: 20260213T175045Z
source: scripts/lib/env.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Environment initialization for v-daemon scripts.
# Usage: env_init REPO_ROOT
  # Idempotent: avoid re-running init when sourced multiple times during command invocation

## Synopsis / Usage


## Reference
- Source: scripts/lib/env.sh


---

## Purpose

---
name: hfsm
generated_by: docs.sh
generated_at: 20260213T175045Z
source: scripts/lib/hfsm.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env bash
# hfsm.sh - Hierarchical Finite State Machine library for shell scripts
#
# Lightweight HFSM implementation for bash. Intended to be sourced by other
# scripts to organize logic into hierarchical states with enter/exit handlers
# and event-based handlers that may trigger transitions.
#
# API:
#  hfsm_create <name>
#  hfsm_add_state <hfsm> <state> [parent]
#  hfsm_set_enter <hfsm> <state> <fn>
#  hfsm_set_exit <hfsm> <state> <fn>

## Synopsis / Usage


## Reference
- Source: scripts/lib/hfsm.sh


---

## Purpose

---
name: logger
generated_by: docs.sh
generated_at: 20260213T175045Z
source: scripts/lib/logger.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Simple logger API for v-daemon scripts.

## Synopsis / Usage


## Reference
- Source: scripts/lib/logger.sh


---

## Purpose

---
name: patcher
generated_by: docs.sh
generated_at: 20260213T175045Z
source: scripts/lib/patcher.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Minimal sandboxed patcher: create a sandbox branch, create a small artifact, commit, run checks, and write artifacts.

## Synopsis / Usage


## Reference
- Source: scripts/lib/patcher.sh


---

## Purpose

---
name: process
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/lib/process.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Process controller: utility functions to manage processes started by scripts.

## Synopsis / Usage


## Reference
- Source: scripts/lib/process.sh


---

## Purpose

---
name: prompts
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/lib/prompts.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# scripts/lib/prompts.sh
# Centralized prompts for the Director agent and Copilot CLI actions.
# Usage: . scripts/lib/prompts.sh
# Then use variables: "$PROMPT_SUMMARIZE_REPO" "$PROMPT_NEXT_STEPS"

## Synopsis / Usage


## Reference
- Source: scripts/lib/prompts.sh


---

## Purpose

---
name: rotate_logs
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/lib/rotate_logs.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Rotate and compress logs in ./logs with timestamped gz archives and retention.

## Synopsis / Usage


## Reference
- Source: scripts/lib/rotate_logs.sh


---

## Purpose

---
name: supervise
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/lib/supervise.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Supervisor loop: ensure daemon is running, restart if it dies, and log activity.

## Synopsis / Usage


## Reference
- Source: scripts/lib/supervise.sh


---

## Purpose

---
name: patch
generated_by: scripts/docs.sh
generated_at: 20260213T162739Z
source: scripts/skills/patch-repo.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env bash


## Synopsis / Usage
Usage: patches.sh [--help]

Automate a simple git patch workflow:
  1. git add .
  2. git commit -m "update:<tree-hash>"
  3. git push (performed by default)

Options:
  --help      Show this help message and exit.

Notes:
  - The commit message uses the index tree hash (git write-tree) to uniquely identify the snapshot: update:<tree-hash>
  - If the current branch has no upstream, the script will run: git push -u origin <branch>
  - This script assumes it's run from inside a git repository and that git is configured.

## Reference
- Source: scripts/skills/patch-repo.sh


---

## Purpose

---
name: patch.sh
generated_by: scripts/docs.sh
generated_at: 20260213T162850Z
source: scripts/patch.sh.bak
autogenerated: true
---

## Purpose
#!/usr/bin/env bash


## Synopsis / Usage
Usage: patches.sh [--help]

Automate a simple git patch workflow:
  1. git add .
  2. git commit -m "update:<tree-hash>"
  3. git push (performed by default)

Options:
  --help      Show this help message and exit.

Notes:
  - The commit message uses the index tree hash (git write-tree) to uniquely identify the snapshot: update:<tree-hash>
  - If the current branch has no upstream, the script will run: git push -u origin <branch>
  - This script assumes it's run from inside a git repository and that git is configured.

## Reference
- Source: scripts/patch.sh.bak


---

## Purpose

---
name: run
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/run.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Supervisor and run helper: starts and monitors the daemon (scripts/lib/daemon.sh)

## Synopsis / Usage


## Reference
- Source: scripts/run.sh


---

## Purpose

---
name: setup
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/setup.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env sh
# Minimal setup script to install C++ build dependencies and ninja for parallel builds

## Synopsis / Usage


## Reference
- Source: scripts/setup.sh


---

## Purpose

---
name: create-agent
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/skills/create-agent.sh
autogenerated: true
---

## Purpose
#!/bin/sh

## Synopsis / Usage


## Reference
- Source: scripts/skills/create-agent.sh


---

## Purpose

---
name: create-skill
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/skills/create-skill.sh
autogenerated: true
---

## Purpose
#!/bin/sh

## Synopsis / Usage


## Reference
- Source: scripts/skills/create-skill.sh


---

## Purpose

---
name: next-steps
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/skills/next-steps.sh
autogenerated: true
---

## Purpose
#!/bin/sh

## Synopsis / Usage


## Reference
- Source: scripts/skills/next-steps.sh


---

## Purpose

---
name: patch-repo
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/skills/patch-repo.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env bash
# If invoked with a POSIX sh (not bash), re-exec with bash to ensure required features are available.

## Synopsis / Usage


## Reference
- Source: scripts/skills/patch-repo.sh


---

## Purpose

---
name: review-repo
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/skills/review-repo.sh
autogenerated: true
---

## Purpose
#!/bin/sh

## Synopsis / Usage


## Reference
- Source: scripts/skills/review-repo.sh


---

## Purpose

---
name: run-app
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/skills/run-app.sh
autogenerated: true
---

## Purpose
#!/bin/sh

## Synopsis / Usage


## Reference
- Source: scripts/skills/run-app.sh


---

## Purpose

---
name: update-docs
generated_by: docs.sh
generated_at: 20260213T175046Z
source: scripts/skills/update-docs.sh
autogenerated: true
---

## Purpose
#!/usr/bin/env bash

## Synopsis / Usage


## Reference
- Source: scripts/skills/update-docs.sh


---

## docs


## Purpose
#!/usr/bin/env bash

## Synopsis / Usage


## Reference
- Source: scripts/docs.sh


---

## actions


## Purpose
#!/usr/bin/env sh
# Director action helpers: autopilot summary (uses copilot CLI only; local fallback removed).

## Synopsis / Usage


## Reference
- Source: scripts/lib/actions.sh


---

## config


## Purpose
#!/usr/bin/env sh
# Configuration loader: reads ./config/settings.toml and exposes runtime variables.
# Usage: . "$REPO_ROOT/scripts/lib/config.sh"; config_init "$REPO_ROOT"

## Synopsis / Usage


## Reference
- Source: scripts/lib/config.sh


---

## console


## Purpose
#!/usr/bin/env sh
# Console helpers: print status and truncated excerpts to console (stderr).

## Synopsis / Usage


## Reference
- Source: scripts/lib/console.sh


---

## daemon


## Purpose
#!/usr/bin/env sh
# Minimal daemon loop. Replace loop body with self-improving logic later.

## Synopsis / Usage


## Reference
- Source: scripts/lib/daemon.sh


---

## director


## Purpose
#!/usr/bin/env sh
# Director agent: coordinates worker agents (minimal stub)

## Synopsis / Usage


## Reference
- Source: scripts/lib/director.sh


---

## env


## Purpose
#!/usr/bin/env sh
# Environment initialization for v-daemon scripts.
# Usage: env_init REPO_ROOT
  # Idempotent: avoid re-running init when sourced multiple times during command invocation

## Synopsis / Usage


## Reference
- Source: scripts/lib/env.sh


---

## hfsm


## Purpose
#!/usr/bin/env bash
# hfsm.sh - Hierarchical Finite State Machine library for shell scripts
#
# Lightweight HFSM implementation for bash. Intended to be sourced by other
# scripts to organize logic into hierarchical states with enter/exit handlers
# and event-based handlers that may trigger transitions.
#
# API:
#  hfsm_create <name>
#  hfsm_add_state <hfsm> <state> [parent]
#  hfsm_set_enter <hfsm> <state> <fn>
#  hfsm_set_exit <hfsm> <state> <fn>

## Synopsis / Usage


## Reference
- Source: scripts/lib/hfsm.sh


---

## logger


## Purpose
#!/usr/bin/env sh
# Simple logger API for v-daemon scripts.

## Synopsis / Usage


## Reference
- Source: scripts/lib/logger.sh


---

## patcher


## Purpose
#!/usr/bin/env sh
# Minimal sandboxed patcher: create a sandbox branch, create a small artifact, commit, run checks, and write artifacts.

## Synopsis / Usage


## Reference
- Source: scripts/lib/patcher.sh


---

## process


## Purpose
#!/usr/bin/env sh
# Process controller: utility functions to manage processes started by scripts.

## Synopsis / Usage


## Reference
- Source: scripts/lib/process.sh


---

## prompts


## Purpose
#!/usr/bin/env sh
# scripts/lib/prompts.sh
# Centralized prompts for the Director agent and Copilot CLI actions.
# Usage: . scripts/lib/prompts.sh
# Then use variables: "$PROMPT_SUMMARIZE_REPO" "$PROMPT_NEXT_STEPS"

## Synopsis / Usage


## Reference
- Source: scripts/lib/prompts.sh


---

## rotate_logs


## Purpose
#!/usr/bin/env sh
# Rotate and compress logs in ./logs with timestamped gz archives and retention.

## Synopsis / Usage


## Reference
- Source: scripts/lib/rotate_logs.sh


---

## supervise


## Purpose
#!/usr/bin/env sh
# Supervisor loop: ensure daemon is running, restart if it dies, and log activity.

## Synopsis / Usage


## Reference
- Source: scripts/lib/supervise.sh


---

## patch


## Purpose
#!/usr/bin/env bash


## Synopsis / Usage
Usage: patches.sh [--help]

Automate a simple git patch workflow:
  1. git add .
  2. git commit -m "update:<tree-hash>"
  3. git push (performed by default)

Options:
  --help      Show this help message and exit.

Notes:
  - The commit message uses the index tree hash (git write-tree) to uniquely identify the snapshot: update:<tree-hash>
  - If the current branch has no upstream, the script will run: git push -u origin <branch>
  - This script assumes it's run from inside a git repository and that git is configured.

## Reference
- Source: scripts/skills/patch-repo.sh


---

## patch.sh


## Purpose
#!/usr/bin/env bash


## Synopsis / Usage
Usage: patches.sh [--help]

Automate a simple git patch workflow:
  1. git add .
  2. git commit -m "update:<tree-hash>"
  3. git push (performed by default)

Options:
  --help      Show this help message and exit.

Notes:
  - The commit message uses the index tree hash (git write-tree) to uniquely identify the snapshot: update:<tree-hash>
  - If the current branch has no upstream, the script will run: git push -u origin <branch>
  - This script assumes it's run from inside a git repository and that git is configured.

## Reference
- Source: scripts/patch.sh.bak


---

## run


## Purpose
#!/usr/bin/env sh
# Supervisor and run helper: starts and monitors the daemon (scripts/lib/daemon.sh)

## Synopsis / Usage


## Reference
- Source: scripts/run.sh


---

## setup


## Purpose
#!/usr/bin/env sh
# Minimal setup script to install C++ build dependencies and ninja for parallel builds

## Synopsis / Usage


## Reference
- Source: scripts/setup.sh


---

## create-agent


## Purpose
#!/bin/sh

## Synopsis / Usage


## Reference
- Source: scripts/skills/create-agent.sh


---

## create-skill


## Purpose
#!/bin/sh

## Synopsis / Usage


## Reference
- Source: scripts/skills/create-skill.sh


---

## next-steps


## Purpose
#!/bin/sh

## Synopsis / Usage


## Reference
- Source: scripts/skills/next-steps.sh


---

## patch-repo


## Purpose
#!/usr/bin/env bash
# If invoked with a POSIX sh (not bash), re-exec with bash to ensure required features are available.

## Synopsis / Usage


## Reference
- Source: scripts/skills/patch-repo.sh


---

## review-repo


## Purpose
#!/bin/sh

## Synopsis / Usage


## Reference
- Source: scripts/skills/review-repo.sh


---

## run-app


## Purpose
#!/bin/sh

## Synopsis / Usage


## Reference
- Source: scripts/skills/run-app.sh


---

## update-docs


## Purpose
#!/usr/bin/env bash

## Synopsis / Usage


## Reference
- Source: scripts/skills/update-docs.sh
