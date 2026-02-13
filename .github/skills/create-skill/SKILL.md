---
name: create-skill
description: "Add a Copilot-discoverable SKILL.md under .github/skills/<name> and optional scripts/skills/<name>.sh scaffold, emitting a run/skills/create-skill report."
---

# SKILL: create-skill

## Summary

Programmatic skill creation utility that adds a SKILL.md under .github/skills/<name>/SKILL.md and (optionally) a companion executable helper script under scripts/skills/<name>.sh. Writes a brief report to run/skills/create-skill/<timestamp>/.

## When to run

- When adding a new SKILL to the repository or provisioning companion scripts.

## Inputs

- name (string, required) — kebab-case name for the new SKILL
- description (string, optional) — short description to populate SKILL.md
- create_script (bool, default: true) — whether to create a companion scripts/skills/<name>.sh

## Outputs

- run/skills/create-skill/<timestamp>/report.txt
- run/skills/create-skill/<timestamp>/report.json
- .github/skills/<name>/SKILL.md (when created)
- scripts/skills/<name>.sh (when requested)

## Collection steps

1. Validate and sanitize provided name.
2. Create .github/skills/<name>/SKILL.md if not present.
3. Create scripts/skills/<name>.sh placeholder if requested.
4. Write a JSON report to run/skills/create-skill/<timestamp>/.

## Quality rules

- Do not overwrite existing SKILL.md or companion scripts; script writes a report and exits if files exist.

## Implementation notes

- Helper script: scripts/skills/create-skill.sh
- Example: sh scripts/skills/create-skill.sh --name new-skill --desc "Short description"
