---
name: next-steps
description: "Generate a small set of prioritized, PR-sized next steps from summary.json."
inputs:
  summary_path:
    type: string
    required: true
  allow_insert_todos:
    type: boolean
    default: false
  allow_execute:
    type: boolean
    default: false
outputs:
  - path: run/skills/next-steps/<timestamp>/tasks.json
  - path: run/skills/next-steps/<timestamp>/tasks.txt
tags:
  - planning
  - tasks
---

# SKILL: next-steps

## Summary

Generate a small set (3–6) of prioritized, PR-sized tasks from `summary.json`. Each task should include acceptance criteria and suggested branch/commit messages.

## When to run

- Immediately after `summarize-repo` completes.

## Inputs

- `summary_path` (required)
- `allow_insert_todos` (bool, default: false)
- `allow_execute` (bool, default: false)
- `max_tasks` (int, default: 6)

## Outputs

- `run/skills/next-steps/<timestamp>/tasks.json`
- `run/skills/next-steps/<timestamp>/tasks.txt`
- Optional SQL inserts into the `todos` table when allowed.

## Task schema (example)

```
{ "id":"add-ci-checks", "title":"Add CI checks to run scripts/setup.sh", "description":"...", "priority":1, "estimate":"2h", "files":["scripts/setup.sh"], "branch":"chore/add-ci-checks", "commit_msg":"chore(ci): add workflow to run scripts/setup.sh" }
```

## Guidelines

- Prefer small, testable tasks with clear acceptance criteria.
- Mark tasks that require network or privileged actions as `requires-approval` or `requires-sandbox`.
- When inserting into `todos`, use kebab-case IDs and include detailed descriptions.
