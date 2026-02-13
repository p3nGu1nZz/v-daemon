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

Agent patching and push verification
- After making persistent repository changes, always invoke the 'patch-repo' skill as the last step (sh scripts/skills/patch-repo.sh or call the 'patch-repo' skill). The skill stages, commits deterministically, and attempts to push upstream.
- Verify push success by checking run/skills/patch-repo/<timestamp>/report.json (pushed:true) and confirming git --no-pager status shows a clean tree. If pushed is false or local changes remain, run git push origin <branch> (retry up to 3 times) and fail the agent if pushes continue to fail.
