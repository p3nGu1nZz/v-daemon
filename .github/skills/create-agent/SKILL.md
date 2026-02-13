---
name: create-agent
description: "Scaffold a non-destructive agent descriptor (.github/agents) and optional runtime script (scripts/agents), producing metadata and an audit report."
---

# SKILL: create-agent

## Summary

Create a new agent scaffold by writing a descriptor file under `.github/agents/<name>.agent.md` and (optionally) a companion executable script under `scripts/agents/<name>.sh`. The skill emits a machine-readable report and a readable summary (informational only) under `run/skills/create-agent/<timestamp>/` describing created files and any early-exit reasons.

## When to run

- When adding a new agent to the repository and you want a consistent agent descriptor and optional runtime script scaffolded.

## Inputs

- `name` (string, required) — kebab-case name for the new agent (script validates and sanitizes name).
- `desc` (string, optional) — short description to populate the agent descriptor.
- `no_script` / `--no-script` (flag, default: false) — when provided, do not create the companion `scripts/agents/<name>.sh` file.

## Outputs

- `run/skills/create-agent/<timestamp>/report.txt` — list of created files or a short reason for early exit.
- `run/skills/create-agent/<timestamp>/report.json` — structured report: `{ "agent": "<name>", "created": true|false, "files": [...] }`.
- `.github/agents/<name>.agent.md` — the generated agent descriptor when created.
- `scripts/agents/<name>.sh` — optional companion executable scaffold when requested.

## Collection / Creation steps

1. Validate and sanitize the provided name (lowercase, safe characters only).
2. Create `run/skills/create-agent/<timestamp>/` and capture outputs there.
3. Create `.github/agents/<name>.agent.md` with a minimal YAML header and Purpose/Notes section; do not overwrite an existing descriptor (exit early and report if it exists).
4. When requested, create `scripts/agents/<name>.sh` as an executable placeholder and include its path in the report.
5. Write `report.txt` and `report.json` summarizing created files and outcomes.

## Quality rules

- Never overwrite existing agent descriptors or scripts; exit cleanly and record a reason in the report when targets already exist.
- Generated descriptor must include at minimum: `name`, `description`, `type: agent`, and `entrypoint` fields in YAML header.
- Companion scripts must be executable and contain a brief placeholder message indicating they are scaffolded.

## Implementation notes

- Recommended helper script: `scripts/skills/create-agent.sh` (included in this repository). It implements the behavior described above.
- Example invocation:

  sh scripts/skills/create-agent.sh --name my-agent --desc "Short description"

- Descriptor template (example):

  ---
  name: <name>
  description: "<desc>"
  type: agent
  entrypoint: "scripts/agents/<name>.sh"
  ---

  # Agent: <name>

  Purpose:
  - <desc>

  Notes:
  - This file was scaffolded by scripts/skills/create-agent.sh
  - Implement agent behavior in scripts/agents/<name>.sh

## Safety

- The skill is non-destructive by default; it will not overwrite existing files.
- Do not run untrusted code as part of this skill; helper scripts should avoid network installs or privileged operations.

## References

- Helper script: `scripts/skills/create-agent.sh`
- Similar skills: `.github/skills/create-skill/SKILL.md`, `.github/skills/update-docs/SKILL.md`, `.github/skills/review-repo/SKILL.md`
