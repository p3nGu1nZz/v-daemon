# TODO: Daemon, Director/Worker Agents, and GitHub MCP Server

## Objective
Build an autonomous daemon that spawns a director agent to coordinate worker agents, and integrate a GitHub MCP Server so the system can create PRs, open issues, and react to repository events.

---

## Milestones & Tasks

### Milestone 1 — Repo & Basic Daemon
- [ ] Repo housekeeping: ensure build scripts, example configs, and README updates.
  - [ ] Add `cmd/daemon` skeleton (config, logging, lifecycle, PID file).
  - [ ] Provide local run script (scripts/run.sh) and basic config sample (config/example.yaml).
- [ ] Implement process supervisor to spawn the director agent as a child process (or managed thread).
- [ ] Add CLI flags for start/stop/status and a clean shutdown path.
- [ ] Add a process controller utility (scripts/lib/process.sh) to register/start/stop managed processes and track run/*.pid files.

**Acceptance criteria:** daemon binary starts, writes logs, spawns the director process, and performs a clean shutdown that also stops the director.

---

### Milestone 2 — Director & Worker basics
- [ ] Director agent core:
  - [ ] Implement a bash heartbeat Director (`dev/harness/director.sh`) that can be started/adopted by the daemon.
  - [ ] Define director API/RPC (lightweight JSON-over-UDS or HTTP) used by daemon and workers.
  - [ ] Implement spawn/stop logic for worker processes and a lightweight registry of active workers.
  - [ ] Implement heartbeat and basic health checks for workers and emit structured director heartbeats into `dev/audits/director.log`.
- [ ] Worker agent:
  - [ ] Implement a worker stub that registers with the director and sends heartbeats.
  - [ ] Implement a simple "work" task (e.g., run a shell command or simulated job) and report status back to director.
- [ ] Integration test: Start supervisor → daemon → director spawns N workers → workers report ready → director assigns a job → workers complete job.

**Acceptance criteria:** Director can spawn workers and coordinate a complete job end-to-end, storing audit bundles under `dev/audits/`.

---

### Milestone 3 — Autonomy & Resilience
- [ ] Implement task queue and autonomous scheduling/decision logic for the director.
- [ ] Add auto-scaling rules, restart policies, and failure handling for workers.
- [ ] Implement health checks, backoff strategies, and optional leader election for distributed runs.
- [ ] Ensure graceful shutdown, upgrade, and state migration paths.

**Acceptance criteria:** System recovers automatically from worker failures and can run unattended for sustained periods.

---

### Milestone 4 — GitHub MCP Server integration
- [ ] Provision a local/dev GitHub MCP Server instance (docker-compose or binary) for development and testing.
- [ ] Secure credentials: create a service account / PAT and document secure storage in env or a vault.
- [ ] Implement an MCP client module in the daemon to create PRs, open issues, post comments, and read repository files.
- [ ] Map GitHub events to director actions (e.g., new issue → spawn worker to run tests; PR → run CI task and post results).
- [ ] Add end-to-end tests that validate PR and issue workflows via the MCP server.

**Acceptance criteria:** Daemon can create a PR and an issue against this repository via the MCP server and react to MCP events.

---

### Milestone 5 — CI, Observability, Security
- [ ] Add integration tests and CI jobs (GitHub Actions or local scripts) for the end-to-end workflow.
- [ ] Add logging and metrics (Prometheus) and basic tracing for director and workers.
- [ ] Review secrets handling and ensure least-privilege access for GitHub tokens and service accounts.
- [ ] Document runbook and operational procedures for debugging and incident response.

---

## Backlog / Nice-to-have
- [ ] Web UI / dashboard for director and worker status.
- [ ] Pluggable agent behaviors (plugin system for worker tasks).
- [ ] Multi-node cluster support and distributed state store (etcd/consul).

---

## How to use this TODO
- Treat each checked item as an independent, testable task and prefer small PRs per task.
- Track progress in GitHub issues and reference TODO.md sections in PR descriptions.
- For local development, start with Milestone 1 and Milestone 2 to get an end-to-end loop.

---

## Notes & Security
- Never commit credentials. Store GitHub tokens in CI secrets or a vault.
- Prefer testing MCP interactions against a local MCP server or a dedicated test org to avoid noisy production effects.

---

*Created as the project single-source TODO for implementing the autonomous daemon, director/worker agents, and GitHub MCP Server integration.*
