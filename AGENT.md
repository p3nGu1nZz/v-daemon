# Agents in v-daemon

This repository defines autonomous agents and skills used by the v-daemon Director and Copilot CLI integrations.

- Use .github/skills/*/SKILL.md to describe skills and run scripts/skills/<name>.sh to produce run/skills/<name>/<timestamp>/ artifacts.
- Agents should be documented here and in .github/agents/*.agent.md, and refer to safety keys in config/settings.toml (e.g. director.allow_execute).

Purpose: provide a top-level overview for contributors and automated validators.
