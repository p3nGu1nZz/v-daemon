# v-daemon

A lightweight supervisor and developer harness for experimenting with a Director/Worker autonomous loop.

v-daemon provides small POSIX shell helpers to set up dependencies, run repository checks, and operate a simple supervisor + agent workflow. Optional native C/C++ components and CMake support are available but not required for most development.

**Status:** Early development — the long-term goal is a safe, iterative engine that summarizes the repository, generates prioritized tasks, and applies small, verifiable changes under automated governance. Decisions about what to implement are determined via discourse by the repository's code-review personas; the Director persona synthesizes votes and makes release decisions aligned with the project's prime directive. There is no separate human-in-the-loop approval step.

## Quickstart

1. Prepare your environment:

   ```sh
   sh scripts/setup.sh --yes
   ```

2. Run repository checks:

   ```sh
   sh scripts/setup.sh --check
   ```

3. Start the supervisor/daemon:

   ```sh
   sh scripts/run.sh [--monitor]
   ```

## Key scripts

- `scripts/setup.sh` — install or prepare dependencies and create `run/` and `logs/`
- `scripts/check.sh` — run repository checks (read-only by default)
- `scripts/run.sh` — start/stop/status the supervisor and daemon

## Requirements

- POSIX `sh` (bash/sh)
- CMake, Ninja, and a C/C++ toolchain only for native builds

## Development

- Prefer small, focused PRs; run `scripts/setup.sh` before pushing.
- Add tests under `build/` and integrate them into `scripts/setup.sh` and CI.

## Docs and resources

- Architecture: `doc/architecture.md`
- Agent docs: `AGENT.md` and `.github/skills/`
- Runtime config: `config/settings.toml`

## Contributing

- Open issues and PRs on GitHub. Keep changes minimal and document acceptance criteria.

- Governance: Decisions are made via discourse by the repository's code-review personas; the Director persona synthesizes votes and determines the iterative release cycle aligned with the project's prime directive (autonomous agent swarm that self-improves, optimizes, and evolves). There is no separate human-in-the-loop approval step; agent personas and the Director govern prioritization and acceptance.
- Never commit secrets.

## License

See the `LICENSE` file at the repository root.
