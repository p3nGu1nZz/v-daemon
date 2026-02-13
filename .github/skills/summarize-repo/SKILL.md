---
name: summarize-repo
description: "Produce a concise, structured summary of the repository suitable for human review and automated planning."
inputs:
  allow_run:
    type: boolean
    default: false
  output_format:
    type: string
    default: text
outputs:
  - path: run/skills/summarize-repo/<timestamp>/summary.txt
  - path: run/skills/summarize-repo/<timestamp>/summary.json
tags:
  - repo
  - summary
---

# SKILL: summarize-repo

## Summary

Produce a concise, structured summary of the repository suitable for human review and automated planning. Outputs: `summary.txt` (human, 4–8 sentences) and `summary.json` (structured).

## When to run

- At Director startup and at the start of each planning cycle.
- Before creating high-level plans or PRs.

## Inputs

- `allow_run` (bool, default: false) — if true, safe checks (e.g., `scripts/setup.sh`) may be executed.
- `output_format` (string): `text` or `json`.
- `include_globs` (array) and `max_preview_lines` (int).

## Outputs

- `run/skills/summarize-repo/<timestamp>/summary.txt`
- `run/skills/summarize-repo/<timestamp>/summary.json`
- Raw captures under `run/skills/summarize-repo/<timestamp>/raw/`

## Collection steps (read-only by default)

1. Capture git metadata and top-level layout.
2. Preview core docs: `README.md`, `AGENT.md`, `doc/architecture.md`.
3. List scripts and capture shebangs/headers.
4. Detect build/test tools (CMake, Catch2).
5. Search for TODO/FIXME.
6. If `allow_run=true`, run `sh scripts/setup.sh --check` in a sandbox and capture logs.

## JSON schema (recommended fields)

```
{ "repo":"", "head":{}, "summary":"", "top_level":[], "scripts":[], "build":{}, "runtime":{}, "tests":{}, "todos":[], "pain_points":[], "recommended_next_steps":[] }
```

## Quality rules

- Human summary: 4–8 sentences; start with repository purpose, list key scripts/configs, and end with recommended next steps.

## Implementation notes

- Always write raw captures to `run/skills/<name>/<timestamp>/raw/`.
- If `allow_run=true`, avoid actions that install packages or change system state without explicit consent.
