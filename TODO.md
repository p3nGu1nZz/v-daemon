# TODO: Fast-track to an autonomous self-improving engine

Recent changes (2026-02-13):

- Centralized environment helpers in scripts/lib/env.sh (env_init) and made it idempotent to avoid double-sourcing; scripts now call env_init once per command scope.
- Hardened many scripts for portability across Linux/macOS/BSD: replaced in-place sed -i with mktemp pattern, added ps_fallback, safer find/grep usage, timeout fallbacks, and directory guards for update-docs.
- Improved SKILL.md short descriptions to help Copilot CLI /skills discovery.


## Prime directive

Build a recursive, autonomous development engine (Director) that can summarize, plan, implement small safe patches, verify results, and iterate under automated governance; human interaction is limited to starting and stopping the system and emergency intervention.

## Milestones

- **Milestone 0 — Run & Supervisor**
  - Acceptance: `scripts/run.sh start` launches supervisor + daemon; pidfiles appear under `run/` and heartbeats are written to `logs/`.

- **Milestone 1 — Summarize & Plan**
  - Acceptance: `review-repo` and `next-steps` write artifacts into `run/skills/<name>/<timestamp>`.

- **Milestone 2 — Safe Patch Execution**
  - Acceptance: sandboxed patcher applies a change, runs `scripts/setup.sh`, and records artifacts under `run/skills/patcher`.

- **Milestone 3 — Autonomous Loop & Resilience**
  - Acceptance: Director loop performs repeated cycles, persists state, and recovers after restarts.

## Immediate priorities

1. Ensure `scripts/setup.sh` creates `run/` and `logs/`, and make `scripts/run.sh` support `start`/`stop`/`status`/`--monitor`.
2. Add director config keys to `config/settings.toml`.
3. Create `scripts/lib/director.sh` skeleton: `summarize -> next-steps -> select task -> patcher -> report`.
4. Implement minimal `summarize` and `next-steps` scripts that write into `run/skills`.
5. Implement `patcher.sh` supporting dry-run and commit modes (guarded by `director.allow_execute`).
6. Update `README.md`, `AGENT.md`, and relevant SKILL.md files to reflect runtime flags and safety controls.

## Safety

By default the Director runs autonomously; optional configuration keys (e.g., `director.allow_execute` and `V_DAEMON_ALLOW_EXECUTE`) can enforce a conservative, read-only mode. All patch attempts should be sandboxed on a branch and produce artifacts for review.
