# AGENT.md — Agent guidance for v-daemon

This document describes actionable skills and run commands for maintainers and automation agents.

## Quick run commands

- Setup: `sh scripts/setup.sh --yes`
- Run checks: `sh scripts/setup.sh --check`
- Start supervisor/harness: `sh scripts/run.sh [--monitor]`

## Primary skills

- `summarize-repo` — produce a concise summary and structured JSON in `run/skills/summarize-repo/<timestamp>`.
- `next-steps` — generate prioritized, PR-sized tasks and optionally insert them into the `todos` table.
- `run-project` — start and manage the supervisor/daemon lifecycle.

## Logging and artifacts

Capture exit codes and store artifacts in `run/` and `logs/` for inspection and reporting.

## Notes

Keep this file in sync with scripts and `.github/skills` so automated helpers can reproduce workflows reliably.
