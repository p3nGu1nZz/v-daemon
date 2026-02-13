# TODO: Fast-track to Autonomous Self-Improving Engine

Prime directive

This repository's prime directive is to create a recursive, fully autonomous development engine powered by the Copilot CLI that self-reviews, prioritizes, implements safe patches, verifies changes, and repeats indefinitely. The immediate objective is to reach a working implementation where `sh scripts/run.sh start` launches a Director loop that can run for extended periods performing continuous improvement cycles.

Milestones

Milestone 0 — Run & Supervisor (Immediate)

- [ ] Ensure scripts/setup.sh creates `run/` and `logs/` and that `scripts/run.sh` supports `start`, `stop`, `status`, and `--monitor`.
- [ ] Ensure supervisor writes `run/v-daemon-supervisor.pid` and daemon writes `run/v-daemon.pid` and emits heartbeats to `logs/daemon.log`.

Acceptance

- `sh scripts/run.sh start` launches the supervisor and daemon; heartbeats appear in logs and pidfiles are created.

Milestone 1 — Summarize & Plan (Short)

- [ ] Implement summarize-repo skill: produce `summary.json` and `summary.txt` under `run/skills/summarize-repo/<timestamp>`.
- [ ] Implement next-steps skill: read `summary.json` and produce prioritized, PR-sized tasks (`tasks.json` and `tasks.txt`) and optionally insert into the `todos` table via SQL.
- [ ] Add settings in `config/settings.toml` for `director.interval_seconds`, `director.sandbox_branch_prefix`, and `director.allow_execute` (default false).

Acceptance

- Director can run a single cycle: summarize -> next-steps -> persist tasks.

Milestone 2 — Safe Patch Execution (Short–Medium)

- [ ] Implement a sandboxed patcher: create a branch, apply a change, run `sh scripts/check.sh`, run tests (if present), and record results under `run/skills/patcher/<timestamp>`.
- [ ] Implement both dry-run and commit/push+PR modes guarded by `director.allow_execute` or env `V_DAEMON_ALLOW_EXECUTE`.

Acceptance

- The patcher can apply a simple change, run checks, and produce success/failure artifacts; branches are prefixed with the sandbox prefix.

Milestone 3 — Autonomous Loop & Resilience (Medium)

- [ ] Integrate Director loop into `scripts/lib/director.sh` and wire it into the daemon so `sh scripts/run.sh start` begins indefinite cycles.
- [ ] Add backoff/retry, crash recovery, log rotation, and monitoring (status endpoint or CLI).
- [ ] Persist task state (either via the `todos` SQL table or filesystem) to survive restarts.

Acceptance

- Long-running Director loop performs repeated cycles, logs activity to `run/self-improve.log`, and recovers after restart.

Immediate prioritized tasks

1. Ensure `run/` and `logs/` creation in `scripts/setup.sh` and `run.sh`.
2. Add director config keys to `config/settings.toml`.
3. Create `scripts/lib/director.sh` skeleton that sequences `summarize -> next-steps -> select task -> patcher -> report -> sleep`.
4. Implement minimal `summarize` and `next-steps` scripts that follow SKILL.md guidance and write artifacts into `run/skills`.
5. Implement `patcher.sh` that can safely apply small edits and validate with `scripts/check.sh`.
6. Update README.md, AGENT.md, and SKILL.md docs to reflect the prime directive and runtime flags (document `V_DAEMON_ALLOW_EXECUTE`).
7. Add simple acceptance tests to `scripts/check.sh` to validate the basic loop (start -> one cycle -> stop).

Safety & operator controls

- Default mode is read-only: `director.allow_execute = false` and `V_DAEMON_ALLOW_EXECUTE` unset.
- Enabling autonomous patch execution requires explicit operator action (config or env var).
- All patch attempts are sandboxed to a branch (prefix `director.sandbox_branch_prefix`) and produce artifacts under `run/skills/patcher` for inspection.

How to run (fast-track)

1. `sh scripts/setup.sh --yes`
2. Optionally enable execute: `export V_DAEMON_ALLOW_EXECUTE=1`
3. `sh scripts/run.sh start`
4. Monitor with: `sh scripts/run.sh status` or `sh scripts/run.sh --monitor start`

Notes

- Keep automatic PRs and patches small and well-tested; prefer human approval for high-risk changes.
- Use the SQL `todos` table or filesystem artifacts for durable coordination between Director cycles.
- Iterate quickly: prefer minimal, verifiable changes that can be validated by `scripts/check.sh` before wider rollout.
