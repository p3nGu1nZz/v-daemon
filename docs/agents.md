# Agents

Shared helpers and conventions for agent scripts.

- Source `scripts/lib/actions.sh` to use shared functions.
- Place helper scripts under `scripts/agents/` or `scripts/lib/`.
- Keep agent scripts small, idempotent, and safe by default.
- Capture artifacts under `run/` and `logs/` for later inspection.
