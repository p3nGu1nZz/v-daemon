# Architecture & Vision

Overview
v-daemon is a lightweight supervisor/daemon and development harness to exercise a Director/Worker autonomous loop (DirectorDev). It favors small, reproducible shell-first workflows while offering optional native components (C/C++) built with CMake.

Core components
- Supervisor (v-daemon): process manager that starts, monitors, and restarts child processes; manages PID files in run/ and writes logs to logs/.
- Director: the decision-making/orchestration component (the 'brain') that assigns work to workers and manages high-level workflows.
- Worker: short-lived or persistent processes that perform tasks assigned by the Director.
- Scripts: scripts/setup.sh, scripts/check.sh, scripts/run.sh and scripts/lib/ provide the developer-facing workflows for setup, validation, and running the supervisor.
- Configuration: ./config/settings.toml controls runtime settings and environment defaults.
- External deps: third-party libraries and test frameworks live under ./external/, e.g., Catch2 for unit testing.

Runtime layout
- run/ — runtime artifacts (PID files, sockets)
- logs/ — persistent logs for runs and test output
- external/ — fetched third-party dependencies
- build/ — out-of-source C/C++ builds (when CMakeLists.txt is added)

Design principles
- Small and reproducible: prefer simple shell scripts for developer workflows that are easy to inspect and modify.
- Optional native extension: support adding C/C++ components with CMake without forcing native toolchain on casual contributors.
- Testability: easy to add unit and integration tests; scripts/setup.sh can fetch Catch2 into external/ for test builds.
- Discoverability: documentation (README, AGENT.md, this architecture doc) should guide both humans and automation.

Vision & roadmap
- Stabilize the supervisor/harness so it can be used for integration experiments and CI.
- Add a formal Director/Worker reference implementation with test coverage.
- Provide container images and systemd units for production deployments.
- Expand automation skills (./.github/skills) and CI integrations for reproducible runs.

How to contribute
- Open small, focused PRs.
- Use scripts/setup.sh to prepare your environment, run scripts/check.sh before pushing, and add tests where appropriate.
- Document changes to scripts in AGENT.md so automation can keep working.

Helpful commands
- sh scripts/setup.sh --yes
- sh scripts/check.sh
- sh scripts/run.sh [--monitor]
