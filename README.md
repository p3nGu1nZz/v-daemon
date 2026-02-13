# v-daemon

v-daemon is a small supervisor/daemon and development harness for exercising a Director/Worker autonomous loop ("DirectorDev"). The repo provides POSIX shell helper scripts to set up dependencies, run repository checks, and exercise a simple supervisor + agent workflow. Native C/C++ components and CMake support are optional and supported when present.

Status: early development — see TODO.md for planned milestones and tasks.

Requirements

- POSIX shell (sh)
- cmake (optional, for C/C++ builds)
- ninja (optional, for C/C++ builds)
- A C/C++ toolchain (g++ or clang) if building native code

Quickstart (Linux)

1. Install/setup required tools and dependencies:

   sh scripts/setup.sh --yes

2. Run repository checks:

   sh scripts/check.sh

3. Build (only if CMakeLists.txt exists):

   mkdir -p build && cd build && cmake -G Ninja .. && ninja -j$(nproc 2>/dev/null || echo 2)

4. Run the supervisor/daemon (development harness):

   sh scripts/run.sh [--monitor]

Development

- scripts/setup.sh can fetch Catch2 into external/Catch2 for unit testing.
- Add a top-level CMakeLists.txt and test targets to enable building tests; then run ctest or ninja test from build/.
- The dev/ directory contains harness scripts and audit logs used during local development.

Repository layout

- dev/ — development harness, example agents, and audit logs
- external/ — third-party dependencies (Catch2, etc.)
- logs/ — durable logs produced by runs
- run/ — runtime artifacts (PID files, sockets)
- scripts/ — helper scripts (setup.sh, check.sh, run.sh, ...)
- TODO.md — project milestones and tasks

Contributing

- Open issues and PRs on GitHub; prefer small, focused PRs.
- Do not commit secrets; store tokens in CI secrets or a vault.

License

See the LICENSE file in the repository root.
