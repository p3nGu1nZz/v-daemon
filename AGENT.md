# AGENT.md — v-daemon agent skills

This file documents agent-facing skills that help maintainers and automation (Copilot agents) interact with the repository runtime. Prime directive: enable a recursive, autonomous development engine that self-reviews, prioritizes, and safely applies patches under the guidance of Copilot CLI—summarize, plan, implement, verify, and repeat.

Skills

## run-project (moved)

See ./.github/skills/run-project/SKILL.md for details.

Agent run commands (examples)
- Setup environment: sh scripts/setup.sh --yes
- Run checks: sh scripts/check.sh
- Run supervisor/harness: sh scripts/run.sh [--monitor]

Agents performing runs should capture exit codes and collect logs (logs/) and runtime artifacts (run/) for reporting. Refer to README.md and ./doc/architecture.md for architecture and design context.

Notes

This AGENT.md is intended to be human- and agent-readable. Keep it updated as run scripts change so automated helpers can reliably reproduce developer workflows.
