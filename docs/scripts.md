# Scripts

All scripts are POSIX `sh` with `#!/usr/bin/env sh` and should be executable (`chmod +x`).

## Common commands

- `sh scripts/setup.sh --yes` — prepare environment and optional dependencies.
- `sh scripts/setup.sh --check` — run repository checks (use in CI).
- `sh scripts/run.sh [--monitor]` — start/stop/status the supervisor and daemon; `--monitor` streams logs.

## Guidelines for new scripts

- Add a short header comment explaining purpose and usage.
- Avoid unguarded package installs; by default the Director will avoid network installs during automated runs; operator consent may be required in conservative deployments.
- Use `run/` and `logs/` for runtime artifacts.
