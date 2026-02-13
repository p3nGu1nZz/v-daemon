# TODO: Fast-track to an autonomous self-improving engine

## Prime directive

Build a recursive, autonomous development engine (Director) that can summarize, plan, implement small safe patches, verify results, and iterate under operator control.

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

Default mode is read-only: `director.allow_execute = false` and `V_DAEMON_ALLOW_EXECUTE` unset. All patch attempts must be sandboxed on a branch and produce artifacts for review.
