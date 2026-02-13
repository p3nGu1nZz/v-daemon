---
name: run-project
description: "Start, monitor, and stop the v-daemon supervisor and daemon."
---

# run-project

## Purpose

Start, monitor, and stop the v-daemon supervisor and daemon. Use this skill to run the project locally or from automation.

## Usage

- Start background: `sh scripts/run.sh start`
- Start and stream: `sh scripts/run.sh --monitor start`
- Stop: `sh scripts/run.sh stop`
- Status: `sh scripts/run.sh status`

## Behavior

- PID files: `run/v-daemon.pid`, `run/v-daemon-supervisor.pid`, `run/v-director.pid`
- Logs: `./logs/daemon.log`, `./logs/supervisor.log`, `./logs/director.log`
- `--monitor` streams logs and traps Ctrl-C for graceful shutdown

## Agent guidance

- Prefer `run.sh` for lifecycle operations. Verify status with `sh scripts/run.sh status` and inspect logs.
- Avoid removing pidfiles manually; use `run.sh stop`.
