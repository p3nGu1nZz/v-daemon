# Monitoring & Director

This document summarizes the interactive monitor (scripts/run.sh --monitor) and Director/autopilot behavior, where to find combined logs, and how to inspect audit artifacts.

## Monitor (run.sh --monitor / status -m)

- Start the monitor: `sh scripts/run.sh status -m` or `sh scripts/run.sh status -m --logs` to include daemon/supervisor logs.
- Flags: `--monitor`/`-m` (enter foreground monitor), `--logs` (stream daemon/supervisor logs into monitor), `--monitor-debug` (record raw input bytes to run/monitor_debug.log).
- Input: The monitor uses /dev/tty for interactive reads; press `Tab` to toggle focus between command input and the tree view, use arrow keys or `j`/`k` as fallbacks to navigate, and type commands (help, kill <pid|name>, ping <id|name>, list, select <n>, focus <cmd|tree>). The monitor stores focus/selection state under `run/monitor_focus` and `run/monitor_selected`.
- Behavior: In monitor-only mode the monitor will not stop processes it didn't start (MONITOR_MANAGES_PROCESS guard). The monitor centers the tailed logs for visibility and supports basic navigation.

## System log (combined runtime log)

- Default combined system log: `run/system.log` (the logger now prefers the run/ directory so runtime state and logs are co-located).
- To view: `tail -n 200 run/system.log` or use the monitor with `--logs` to stream supervisor and daemon logs live.

## Director & Autopilot

- Entrypoint: `scripts/lib/actions.sh` — the Director constructs a repository snapshot, invokes the Copilot CLI to produce summaries and plans, and writes per-run diagnostics to `audits/director-summary-<ts>/`.
- Copilot: The autopilot requires the Copilot CLI (no local summarizer fallback). The scripts set `COPILOT_MODEL=gpt-5-mini` by default; you can override with `COPILOT_MODEL` env var.
- Timeout: Configure `DIRECTOR_COPILOT_TIMEOUT_SECONDS` to control Copilot invocation timeout; default is 300 seconds.
- Diagnostics: Each autopilot run writes a directory under `audits/director-summary-<ts>/` containing `copilot.err`, `copilot_raw.txt`, `copilot_sanitized.txt`, `ps_snapshot.txt`, `copilot.pid`, `copilot.pgid`, and `summary.txt`.

## Patching and patch-repo

- `scripts/skills/patch-repo.sh` stages changes, creates a deterministic commit (message `update:<tree-hash>`), and does NOT push by default (use `--push` to enable pushing). The script writes a report to `run/skills/patch-repo/<timestamp>/report.json` which includes `commit`, `pushed`, and `status` fields — inspect this report after any automated patch attempt.
- Safety: The repository includes `config/settings.toml` and runtime guards (e.g., `director.allow_execute`) that should be reviewed before enabling automatic patching in production.

## Troubleshooting

- If the Director reports "run_autopilot_summary failed or timed out", inspect the latest `audits/director-summary-*/copilot.err` and `ps_snapshot.txt` for process-level diagnostics and stderr output.
- If the monitor becomes unresponsive, start it with `--monitor-debug` to capture raw input bytes to `run/monitor_debug.log` for analysis.

---

For more details, see `AGENT.md` and `scripts/lib/actions.sh` (the source of the autopilot workflow).
