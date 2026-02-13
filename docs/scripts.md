Scripts

All scripts in scripts/ are implemented in POSIX sh and must use the shebang: /usr/bin/env sh. Ensure scripts are executable (chmod +x).

Common usage:
- sh scripts/setup.sh --yes  # fetch deps and create required directories (run/, logs/)
- sh scripts/check.sh        # run repository checks and verify POSIX sh compliance
- sh scripts/run.sh [--monitor]  # start/stop/status supervisor & daemon

Runtime settings
Runtime settings live in ./config/settings.toml; update that file to change log and run paths or heartbeat intervals.

See TODO.md for planned milestones and additional notes.
