# Copilot instructions for v-daemon

A concise reference for common commands and repository conventions.

## Build

- Check environment: `sh scripts/setup.sh --check`
- Install dependencies: `sh scripts/setup.sh --yes`
- Example native build (if present):

  ```sh
  mkdir -p build && cd build && cmake -G Ninja .. && ninja -j$(nproc 2>/dev/null || echo 2)
  ```

## Test

- No test runner is configured by default. If tests are added, run them from `build/` (ctest or `ninja test`).

## Run

- `sh scripts/run.sh start` — start supervisor & daemon
- `sh scripts/run.sh --monitor start` — start and stream logs
- `sh scripts/run.sh stop/status` — stop and check status

## Conventions

- Scripts use POSIX `sh` and must be executable.
- Use an out-of-source build directory (`build/`).
- Keep PRs small and include acceptance criteria.
