# TODO: Daemon, Director/Worker Agents, and GitHub MCP Server

## Objective

Build an autonomous daemon that spawns a director agent to coordinate worker agents, and integrate a GitHub MCP Server so the system can create PRs, open issues, and react to repository events.

---

## Milestone 1 — Repo & Basic Daemon

Phase: Setup & housekeeping

- [ ] Ensure build scripts, example configs, and README updates
- [ ] Add config/example.yaml (sample configuration)
- [ ] Provide local run script (scripts/run.sh) and examples
- [ ] Add scripts/lib/process.sh to register/start/stop managed processes and track run/*.pid files

Phase: Daemon skeleton & supervisor

- [ ] Add cmd/daemon skeleton (config, logging, lifecycle, PID file)
- [ ] Implement process supervisor to spawn the director agent as a child process
- [ ] Add CLI flags: start/stop/status and a clean shutdown path

Acceptance criteria

- daemon binary starts, writes logs, spawns the director process, and performs a clean shutdown that also stops the director.

---

## Milestone 2 — Director & Worker basics

Phase: Director core

- [ ] Implement a simple director (shell or lightweight binary) usable by the daemon (e.g., dev/harness/director.sh)
- [ ] Define director API/RPC (JSON-over-UDS or HTTP) used by daemon and workers
- [ ] Implement spawn/stop logic and a registry of active workers
- [ ] Emit structured director heartbeats into dev/audits/director.log

Phase: Worker agent

- [ ] Implement a worker stub that registers with the director and sends heartbeats
- [ ] Implement a simple "work" task (shell command or simulated job) and report status back to director

Phase: Integration tests

- [ ] End-to-end: Start supervisor → daemon → director spawns N workers → workers report ready → director assigns job → workers complete job and emit audits under dev/audits/

Acceptance criteria

- Director can spawn workers and coordinate a complete job end-to-end.

---

## Milestone 3 — Autonomy & Resilience

Phase: Scheduling & resilience

- [ ] Implement a task queue and autonomous scheduling/decision logic for the director
- [ ] Add auto-scaling rules, restart policies, and failure handling for workers
- [ ] Implement health checks, backoff strategies, and optional leader election
- [ ] Ensure graceful shutdown, upgrade, and state migration paths

Acceptance criteria

- System recovers automatically from worker failures and can run unattended for sustained periods.

---

## Milestone 4 — GitHub MCP Server integration

Phase: Dev environment

- [ ] Provision a local/dev GitHub MCP Server instance (docker-compose or binary) for development and testing
- [ ] Document secure credential storage (service account / PAT in env or vault)

Phase: MCP client & mapping

- [ ] Implement an MCP client module in the daemon to create PRs, open issues, post comments, and read repository files
- [ ] Map GitHub events to director actions (issue → spawn worker; PR → run CI tasks)
- [ ] Add end-to-end tests that validate PR and issue workflows via the MCP server

Acceptance criteria

- Daemon can create a PR and an issue via the MCP server and react to MCP events.

---

## Milestone 5 — CI, Observability, Security

Phase: CI & tests

- [ ] Add integration tests and CI jobs (GitHub Actions or local scripts) for the end-to-end workflow

Phase: Observability & ops

- [ ] Add logging, metrics (Prometheus), and basic tracing for director and workers
- [ ] Document runbooks and operational procedures for debugging and incident response
- [ ] Review secrets handling and ensure least-privilege access for GitHub tokens and service accounts

---

## Backlog / Nice-to-have

- [ ] Web UI / dashboard for director and worker status
- [ ] Pluggable agent behaviors (plugin system for worker tasks)
- [ ] Multi-node cluster support and distributed state store (etcd/consul)

---

## How to use this TODO

- Treat each checked item as an independent, testable task and prefer small PRs per task
- Track progress in GitHub issues and reference TODO.md sections in PR descriptions
- For local development, start with Milestone 1 and Milestone 2 to get an end-to-end loop

---

## Notes & Security

- Never commit credentials. Store GitHub tokens in CI secrets or a vault
- Prefer testing MCP interactions against a local MCP server or a dedicated test org to avoid noisy production effects

---

*Flattened and reorganized from the original TODO; each milestone is split into phases with flat, itemized tasks.*
