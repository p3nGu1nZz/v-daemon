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
