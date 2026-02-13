# TODO: Daemon, Director/Worker Agents, and GitHub MCP Server

## Objective

Focus immediately on Milestone 1: provide a working repository and a minimal supervisor/daemon development harness implemented entirely with POSIX sh scripts.

Constraints

- All code and scripting remains pure POSIX sh (use /usr/bin/env sh shebang). Do not add bash-only features or other languages.
- Do not introduce SQLite or any database; store runtime state in the filesystem under run/ and logs/.

---

## Milestone 1 — Repo & Basic Daemon (Immediate focus)

Phase: Setup & housekeeping

- [ ] Ensure all scripts (scripts/*.sh and scripts/lib/*.sh) use a POSIX sh shebang (/usr/bin/env sh) and are executable
- [ ] Verify scripts are pure POSIX sh (remove bashisms) and document any required sh portability notes in docs/scripts.md
- [ ] Create or update config/settings.toml with minimal runtime settings (log paths, run paths, intervals)
- [ ] Ensure run/ and logs/ exist and are referenced by scripts (move pidfiles/locks from /tmp into run/)
- [ ] Update README.md quickstart to reflect POSIX sh usage and the supervisor/run workflow

Phase: Daemon skeleton & supervisor

- [ ] Verify scripts/lib/daemon.sh writes its pidfile into run/v-daemon.pid, uses a robust lock (mkdir+pid or flock helper), and emits heartbeats to logs/daemon.log
- [ ] Verify scripts/lib/supervise.sh monitors the daemon, writes supervisor logs to logs/supervisor.log, and creates run/v-daemon-supervisor.pid
- [ ] Verify scripts/run.sh implements start/stop/status and a --monitor mode that tails logs and shows a one-line system status
- [ ] Ensure scripts/lib/process.sh provides register/start/stop utilities that use run/*.pid and logs/*.log and is POSIX sh

Acceptance criteria

- Running: sh scripts/run.sh start launches the supervisor (run/v-daemon-supervisor.pid), which starts or adopts a daemon (run/v-daemon.pid)
- The daemon writes periodic heartbeats to logs/daemon.log and starts the director (run/v-director.pid) under the same POSIX sh scripts
- sh scripts/run.sh stop cleanly stops supervisor, daemon, and director and removes pidfiles/locks under run/
- README.md documents the above quickstart and paths

---

## Notes & Security

- No SQLite or databases — filesystem-only state for now.
- Use mktemp for temporary files and ensure cleanup via traps in scripts that create temp files.
- Prefer pgrep -f where available for process discovery; if unavailable, use /proc checks as a portable fallback.

---

*This file focuses the project on Milestone 1 and enforces pure POSIX sh and filesystem-backed runtime state; other milestones are deferred until Milestone 1 is complete.*
