# Architecture & Vision

## Overview

v-daemon is a small supervisor and development harness to explore a Director/Worker autonomous loop. It prioritizes small, auditable shell-first workflows with optional native extensions.

## Components

- **Supervisor**: manages processes, PID files, restarts, and logs.
- **Director**: orchestrates planning cycles and assigns work.
- **Worker**: executes assigned tasks.
- **Scripts**: `scripts/setup.sh`, `scripts/setup.sh`, `scripts/run.sh`, and `scripts/lib/` provide developer workflows.
- **Configuration**: `config/settings.toml` controls runtime behavior.

## Principles

- Small and auditable: prefer POSIX shell for discoverability.
- Optional native: allow C/C++ components without requiring toolchains.
- Safe by default: sandbox execution and require explicit operator consent for mutations.
- Testable: make changes verifiable via `scripts/setup.sh`.

## Runtime layout

- `run/`: PID files and runtime artifacts
- `logs/`: persistent logs
- `external/`: fetched dependencies
- `build/`: optional out-of-source builds

## Roadmap

- Stabilize the supervisor and add CI checks.
- Add a reference Director/Worker implementation and container images.
- Expand automation skills and CI integrations.
