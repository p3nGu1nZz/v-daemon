# AGENT.md — v-daemon agent skills

This file documents agent-facing skills that help maintainers and automation (Copilot agents) interact with the repository runtime.

Skills

## run-project

Purpose

Start, monitor, and stop the v-daemon supervisor and daemon. Use this skill when you need to run the project locally, stream logs, or shut it down cleanly.

Usage examples

- Start in background: sh scripts/run.sh start
- Start in foreground & stream logs: sh scripts/run.sh --monitor start  (or sh scripts/run.sh start --monitor)
- Stop: sh scripts/run.sh stop
- Status: sh scripts/run.sh status

Behavior and stopping

- PID files: /tmp/v-daemon.pid (daemon), /tmp/v-daemon-supervisor.pid (supervisor), /tmp/v-director.pid (director)
- Logs: ./logs/daemon.log, ./logs/supervisor.log, ./logs/director.log
- When running with --monitor, pressing Ctrl-C triggers a graceful shutdown. The monitor trap calls cleanup_and_exit which runs stop_all and exits with code 130.
- For non-interactive or remote shutdowns, prefer: sh scripts/run.sh stop — this will attempt a graceful stop, kill orphans, rotate logs, and remove pidfiles.
- Only use kill -TERM <pid> or kill -9 <pid> as a last resort after inspecting logs and pidfiles.

Agent guidance

- Prefer run.sh for lifecycle operations (start/stop/status). It handles pidfiles, orphan cleanup, and log rotation.
- After starting, verify with: sh scripts/run.sh status and inspect ./logs/*.log for healthy heartbeats.
- Avoid removing pidfiles manually unless you have verified the process is not running (use ps or kill -0).

Examples for agents

- Start and monitor interactively (recommended for debugging):

  sh scripts/run.sh --monitor start

  Then press Ctrl-C to stop everything cleanly.

- Start in background from CI or automation:

  sh scripts/run.sh start
  sh scripts/run.sh status

- Stop from automation:

  sh scripts/run.sh stop
  sh scripts/run.sh status

Notes

This AGENT.md is intended to be human- and agent-readable. Keep it updated as run scripts change so automated helpers can reliably reproduce developer workflows.
